
namespace :rubber do
  
  namespace :munin do
  
    rubber.allow_optional_tasks(self)
    
    # after "deploy:stop", "rubber:munin:stop"
    # before "deploy:start", "rubber:munin:start"
    # after "deploy:restart", "rubber:munin:restart"

    desc "Start munin system monitoring"
    task :start do
      run "/etc/init.d/munin-node start"
    end
    
    desc "Stop munin system monitoring"
    task :stop, :on_error => :continue do
      run "/etc/init.d/munin-node stop"
    end
    
    desc "Restart munin system monitoring"
    task :restart do
      stop
      start
    end
  
  end

end
