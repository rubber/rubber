namespace :rubber do

  namespace :redis do

    rubber.allow_optional_tasks(self)

    after "rubber:install_packages", "rubber:redis:custom_install"

    task :custom_install, :roles => :redis do
      custom_package('http://ftp.us.debian.org/debian/pool/main/r/redis/', 'redis-server', '1.2.6-1', '! -x /usr/bin/redis-server')
      # force redis config regen so db dir gets recreated when creating staging from a bundle
      rsudo "rm -f /etc/redis/redis.conf"
    end

    desc "Stops the redis server"
    task :stop, :roles => :redis do
      rsudo "/etc/init.d/redis-server stop; exit 0"
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
