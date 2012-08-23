namespace :rubber do

  namespace :graylog do

    namespace :server do

      rubber.allow_optional_tasks(self)

      after "rubber:install_packages", "rubber:graylog:server:install"

      task :install, :roles => :graylog_server do
        rubber.sudo_script 'install_graylog_server', <<-ENDSCRIPT
          if [[ ! -d "#{rubber_env.graylog_server_dir}" ]]; then
            wget --no-check-certificate -qNP /tmp #{rubber_env.graylog_server_pkg_url}
            tar -C #{rubber_env.graylog_server_prefix} -zxf /tmp/graylog2-server-#{rubber_env.graylog_server_version}.tar.gz
          fi
        ENDSCRIPT
      end

      after "rubber:mongodb:bootstrap", "rubber:graylog:server:multi_dependency_bootstrap"
      after "rubber:elasticsearch:bootstrap", "rubber:graylog:server:multi_dependency_bootstrap"
      dependency_count = 0
      task :multi_dependency_bootstrap do
        dependency_count += 1
        if dependency_count == 2
          bootstrap
        end
      end

      task :bootstrap, :roles => :graylog_server do
        exists = capture("echo $(ls /etc/graylog2.conf 2> /dev/null)")
        if exists.strip.size == 0
          rubber.update_code_for_bootstrap
          rubber.run_config(:file => "role/graylog_server/", :force => true, :deploy_path => release_path)

          restart
        end
      end

      desc "Stops the graylog server"
      task :stop, :roles => :graylog_server, :on_error => :continue do
        rsudo "service graylog-server stop || true"
      end

      desc "Starts the graylog server"
      task :start, :roles => :graylog_server do
        rsudo "service graylog-server start"
      end

      desc "Restarts the graylog server"
      task :restart, :roles => :graylog_server do
        stop
        start
      end

    end

    namespace :web do

      rubber.allow_optional_tasks(self)

      after "rubber:install_packages", "rubber:graylog:web:install"

      task :install, :roles => :graylog_web do
        rubber.sudo_script 'install_graylog_web', <<-ENDSCRIPT
          if [[ ! -d "#{rubber_env.graylog_web_dir}" ]]; then
            wget --no-check-certificate -qNP /tmp #{rubber_env.graylog_web_pkg_url}
            tar -C #{rubber_env.graylog_web_prefix} -zxf /tmp/graylog2-web-interface-#{rubber_env.graylog_web_version}.tar.gz

            mkdir #{rubber_env.graylog_web_dir}/log
            mkdir #{rubber_env.graylog_web_dir}/tmp
          fi
        ENDSCRIPT
      end

      after "rubber:graylog:server:bootstrap", "rubber:graylog:web:bootstrap"

      task :bootstrap, :roles => :graylog_web do
        exists = capture("echo $(ls #{rubber_env.graylog_web_dir}/log 2> /dev/null)")
        if exists.strip.size == 0
          rubber.update_code_for_bootstrap

          rubber.run_config(:file => "role/graylog_web/", :force => true, :deploy_path => release_path)

          rubber.sudo_script 'bootstrap_graylog_web', <<-ENDSCRIPT
            cd #{rubber_env.graylog_web_dir}

            # Add puma to the Gemfile so we can run the server.
            echo "gem 'puma'" >> Gemfile

            export RAILS_ENV=production
            bundle install

            # Create the Graylog Web admin account.
            ./script/rails runner "User.create(:login => '#{rubber_env.graylog_web_username}', :email => '#{rubber_env.graylog_web_email}', :password => '#{rubber_env.graylog_web_password}', :password_confirmation => '#{rubber_env.graylog_web_password}', :role => 'admin') if User.count == 0"
          ENDSCRIPT

          restart
        end
      end

      desc "Stops the graylog web"
      task :stop, :roles => :graylog_web, :on_error => :continue do
        rsudo "service graylog-web stop || true"
      end

      desc "Starts the graylog web"
      task :start, :roles => :graylog_web do
        rsudo "service graylog-web start"
      end

      desc "Restarts the graylog web"
      task :restart, :roles => :graylog_web do
        stop
        start
      end

    end

  end

end
