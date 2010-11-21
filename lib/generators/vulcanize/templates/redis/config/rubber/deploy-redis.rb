namespace :rubber do

  namespace :redis do

    rubber.allow_optional_tasks(self)

    before "rubber:install_packages", "rubber:redis:setup_apt_sources"

    task :setup_apt_sources, :roles => :redis do
      rsudo "add-apt-repository ppa:soren/nova"
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

          mv redis-benchmark /usr/bin/
          mv redis-check-aof /usr/bin/
          mv redis-check-dump /usr/bin/
          mv redis-cli /usr/bin/
          mv redis-server /usr/bin/

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
