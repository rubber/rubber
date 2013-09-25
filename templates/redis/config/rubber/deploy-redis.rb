namespace :rubber do

  namespace :redis do

    rubber.allow_optional_tasks(self)

    after "rubber:install_packages", "rubber:redis:install"

    task :install, :roles => :redis do
      rubber.sudo_script 'install_redis', <<-ENDSCRIPT
        if ! redis-server --version | grep "#{rubber_env.redis_server_version}" &> /dev/null; then
          # Fetch the sources.
          wget http://download.redis.io/releases/redis-#{rubber_env.redis_server_version}.tar.gz
          tar -zxf redis-#{rubber_env.redis_server_version}.tar.gz

          # Build the binaries.
          cd redis-#{rubber_env.redis_server_version}
          make

          # Install the binaries.
          make install

          # create the user
          if ! id redis &> /dev/null; then adduser --system --group redis; fi

          # Clean up after ourselves.
          cd ..
          rm -rf redis-#{rubber_env.redis_server_version}
          rm redis-#{rubber_env.redis_server_version}.tar.gz
        fi
      ENDSCRIPT
    end

    after "rubber:bootstrap", "rubber:redis:bootstrap"

    task :bootstrap, :roles => :redis do
      exists = capture("echo $(ls #{rubber_env.redis_db_dir} 2> /dev/null)")
      if exists.strip.size == 0

        rubber.sudo_script 'bootstrap_redis', <<-ENDSCRIPT
          mkdir -p #{rubber_env.redis_db_dir}
          chown -R redis:redis #{rubber_env.redis_db_dir}
        ENDSCRIPT

        # After everything installed on machines, we need the source tree
        # on hosts in order to run rubber:config for bootstrapping the db
        rubber.update_code_for_bootstrap

        # Gen just the conf for redis.
        rubber.run_config(:file => "role/redis/", :force => true, :deploy_path => release_path)

        restart
      end
    end

    desc "Stops the redis server"
    task :stop, :roles => :redis, :on_error => :continue do
      rsudo "service redis-server stop || true"
    end

    desc "Starts the redis server"
    task :start, :roles => :redis do
      rsudo "service redis-server start"
    end

    desc "Restarts the redis server"
    task :restart, :roles => :redis do
      stop
      start
    end

    desc "Reloads the redis server"
    task :reload, :roles => :redis do
      restart
    end

  end

end
