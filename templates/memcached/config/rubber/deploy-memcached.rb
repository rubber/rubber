
namespace :rubber do
  
  namespace :memcached do

    desc "Display status of memcached shared memory"
    task :status, :roles => :memcached do
      rsudo "service memcached status || true"
      rsudo "ps -eopid,user,cmd | grep [m]emcached || true"
      rsudo "netstat -tulpn | grep memcached || true"
    end

  end

end
