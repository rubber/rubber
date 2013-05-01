
namespace :rubber do
  
  namespace :monit do
  
    rubber.allow_optional_tasks(self)
    
    # monit needs to get stopped first and started last so that it doesn't
    # mess with us restarting everything as part of a deploy.
    before "rubber:pre_stop", "rubber:monit:stop"
    before "rubber:pre_restart", "rubber:monit:stop"
    after "rubber:post_start", "rubber:monit:start"
    after "rubber:post_restart", "rubber:monit:start"

    desc "Start monit daemon monitoring"
    task :start, :roles => :monit do
      rsudo "service monit status || service monit start"
    end
    
    desc "Stop monit daemon monitoring"
    task :stop, :roles => :monit do
      rsudo "service monit stop || true"
    end
    
    desc "Restart monit daemon monitoring"
    task :restart, :roles => :monit do
      stop
      start
    end

    desc "Display status of monit daemon monitoring"
    task :status, :roles => :monit do
      rsudo "service monit status || true"
      rsudo "ps -eopid,user,fname | grep [m]onit || true"
      rsudo "netstat -tulpn | grep monit || true"
    end

  end

end
