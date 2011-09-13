namespace :rubber do

  namespace :redis do

    rubber.allow_optional_tasks(self)

    before "rubber:install_packages", "rubber:redis:setup_apt_sources"

    task :setup_apt_sources, :roles => :redis do
      rubber.sudo_script 'configure_redis_repository', <<-ENDSCRIPT
        # redis 2.0 is the default starting in Ubuntu 11.04.
        if grep '10\.' /etc/lsb-release; then
          add-apt-repository ppa:soren/nova
        fi
      ENDSCRIPT
    end

    after "rubber:install_packages", "rubber:redis:custom_install"

    task :custom_install, :roles => :redis do
      rubber.sudo_script 'install_redis', <<-ENDSCRIPT
        if ! redis-server --version | grep "#{rubber_env.redis_server_version}" &> /dev/null; then
          # Fetch the sources.
          wget http://redis.googlecode.com/files/redis-#{rubber_env.redis_server_version}.tar.gz
          tar -zxf redis-#{rubber_env.redis_server_version}.tar.gz

          # Build the binaries.
          cd redis-#{rubber_env.redis_server_version}
          make

          # Install the binaries.
          /etc/init.d/redis-server stop

          mv src/redis-benchmark /usr/bin/
          mv src/redis-check-aof /usr/bin/
          mv src/redis-check-dump /usr/bin/
          mv src/redis-cli /usr/bin/
          mv src/redis-server /usr/bin/

          /etc/init.d/redis-server start

          # Clean up after ourselves.
          cd ..
          rm -rf redis-#{rubber_env.redis_server_version}
          rm redis-#{rubber_env.redis_server_version}.tar.gz
        fi
      ENDSCRIPT
    end

    after "rubber:bootstrap", "rubber:redis:bootstrap"

    task :bootstrap, :roles => :redis do
      rubber.sudo_script 'bootstrap_redis', <<-ENDSCRIPT
        mkdir -p #{rubber_env.redis_db_dir}
        chown -R redis:redis #{rubber_env.redis_db_dir}
      ENDSCRIPT

      # After everything installed on machines, we need the source tree
      # on hosts in order to run rubber:config for bootstrapping the db
      rubber.update_code_for_bootstrap

      # Gen just the conf for cassandra
      rubber.run_config(:RUBBER_ENV => RUBBER_ENV, :FILE => "role/redis", :FORCE => true, :deploy_path => release_path)
    end

    desc "Stops the redis server"
    task :stop, :roles => :redis, :on_error => :continue do
      rsudo "/etc/init.d/redis-server stop"
    end

    desc "Starts the redis server"
    task :start, :roles => :redis do
      rsudo "/etc/init.d/redis-server start"
    end

    desc "Restarts the redis server"
    task :restart, :roles => :redis do
      rsudo "/etc/init.d/redis-server restart"
    end

    desc "Reloads the redis server"
    task :reload, :roles => :redis do
      rsudo "/etc/init.d/redis-server restart"
    end

  end

end
