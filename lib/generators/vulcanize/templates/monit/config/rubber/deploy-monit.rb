
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
    task :start do
      rsudo "service monit start"
    end
    
    desc "Stop monit daemon monitoring"
    task :stop do
      rsudo "service monit stop; exit 0"
    end
    
    desc "Restart monit daemon monitoring"
    task :restart do
      stop
      start
    end
  
  end

end
