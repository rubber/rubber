
namespace :rubber do
  
  namespace :memcached do

    desc "Starts memcached shared memory"
    task :start, :roles => :memcached do
      rsudo "service memcached status || service memcached start"
    end

    desc "Stops memcached shared memory"
    task :stop, :roles => :memcached do
      rsudo "service memcached stop || true"
    end

    desc "Restarts memcached shared memory"
    task :restart, :roles => :memcached do
      stop
      start
    end

    desc "Display status of memcached shared memory"
    task :status, :roles => :memcached do
      rsudo "service memcached status || true"
      rsudo "ps -eopid,user,cmd | grep [m]emcached || true"
      rsudo "netstat -tulpn | grep memcached || true"
    end

  end

end
