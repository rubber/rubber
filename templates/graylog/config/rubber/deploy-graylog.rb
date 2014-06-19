namespace :rubber do

  namespace :graylog do

    namespace :server do

      rubber.allow_optional_tasks(self)

      after "rubber:install_packages", "rubber:graylog:server:install"

      task :install, :roles => :graylog_server do
        rubber.sudo_script 'install_graylog_server', <<-ENDSCRIPT
          if [[ ! -d "#{rubber_env.graylog_server_dir}" ]]; then
            wget --no-check-certificate -qNP /tmp https://github.com/Graylog2/graylog2-server/releases/download/#{rubber_env.graylog_server_version}/graylog2-server-#{rubber_env.graylog_server_version}.tgz
            tar -C #{rubber_env.graylog_server_prefix} -zxf /tmp/graylog2-server-#{rubber_env.graylog_server_version}.tgz
            rm /tmp/graylog2-server-#{rubber_env.graylog_server_version}.tgz
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

      before "rubber:graylog:server:bootstrap", "rubber:mongodb:restart"

      task :bootstrap, :roles => :graylog_server do
        exists = capture("echo $(ls /etc/graylog2.conf 2> /dev/null)")
        if exists.strip.size == 0
          rubber.update_code_for_bootstrap
          rubber.run_config(:file => "role/graylog_server/", :force => true, :deploy_path => release_path)

          restart
        end
      end

      after "rubber:graylog:server:bootstrap", "rubber:graylog:server:create_inputs"

      task :create_inputs, :roles => :graylog_web do
        rubber.sudo_script 'create_inputs', <<-ENDSCRIPT
          # Only create inputs if the system has 0 inputs.  It's a bit of a rough hack, but graylog currently (v0.20.2)
          # doesn't prevent the creation of duplicate conflicting inputs.
          if ! curl -s --user #{rubber_env.graylog_web_username}:#{rubber_env.graylog_web_password} -XGET http://localhost:12900/system/inputs | grep "GELFUDPInput" &> /dev/null; then
            curl --user #{rubber_env.graylog_web_username}:#{rubber_env.graylog_web_password} -XPOST http://localhost:12900/system/inputs -H "Content-Type: application/json" -d '{"type": "org.graylog2.inputs.gelf.udp.GELFUDPInput", "creator_user_id": "admin", "title": "gelf-udp", "global": true, "configuration": { "port": #{rubber_env.graylog_server_port}, "bind_address": "0.0.0.0" } }'
          fi

          if ! curl -s --user #{rubber_env.graylog_web_username}:#{rubber_env.graylog_web_password} -XGET http://localhost:12900/system/inputs | grep "SyslogUDPInput" &> /dev/null; then
            curl --user #{rubber_env.graylog_web_username}:#{rubber_env.graylog_web_password} -XPOST http://localhost:12900/system/inputs -H "Content-Type: application/json" -d '{"type": "org.graylog2.inputs.syslog.udp.SyslogUDPInput", "creator_user_id": "admin", "title": "syslog-udp", "global": true, "configuration": { "port": #{rubber_env.graylog_server_syslog_port}, "bind_address": "0.0.0.0" } }'
          fi
        ENDSCRIPT
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
            wget --no-check-certificate -qNP /tmp https://github.com/Graylog2/graylog2-web-interface/releases/download/#{rubber_env.graylog_web_version}/graylog2-web-interface-#{rubber_env.graylog_web_version}.tgz
            tar -C #{rubber_env.graylog_web_prefix} -zxf /tmp/graylog2-web-interface-#{rubber_env.graylog_web_version}.tgz
            rm /tmp/graylog2-web-interface-#{rubber_env.graylog_web_version}.tgz
          fi
        ENDSCRIPT
      end

      after "rubber:graylog:server:bootstrap", "rubber:graylog:web:bootstrap"

      task :bootstrap, :roles => :graylog_web do
        exists = capture("echo $(ls #{rubber_env.graylog_web_dir}/log 2> /dev/null)")
        if exists.strip.size == 0
          rubber.update_code_for_bootstrap

          rubber.run_config(:file => "role/graylog_web/", :force => true, :deploy_path => release_path)

          restart
          sleep 5 # Give graylog-web a bit of time to start up.
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
