
namespace :rubber do
  
  namespace :memcached do

    desc "Display status of memcached shared memory"
    task :status, :roles => :memcached do
      rsudo "ps -eopid,user,cmd | grep [m]emcached"
      rsudo "netstat -tulpn | grep memcached"
    end

  end

end
