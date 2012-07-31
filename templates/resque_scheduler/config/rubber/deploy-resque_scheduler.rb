namespace :rubber do

  namespace :resque_scheduler do

    rubber.allow_optional_tasks(self)

    before "deploy:stop", "rubber:resque_scheduler:stop"
    after "deploy:start", "rubber:resque_scheduler:start"
    after "deploy:restart", "rubber:resque_scheduler:restart"
    
    desc "Stops the resque_scheduler"
    task :stop, :roles => :resque_scheduler do
      rsudo "service resque-scheduler stop || true"
    end

    desc "Starts the resque_scheduler"
    task :start, :roles => :resque_scheduler do
      rsudo "service resque-scheduler start"
    end

    desc "Restarts the resque_scheduler"
    task :restart, :roles => :resque_scheduler do
      stop
      start      
    end

    # pauses deploy until daemon is up so monit doesn't try and start it
    before "rubber:monit:start", "rubber:resque_scheduler:wait_start"
    task :wait_start, :roles => :resque_scheduler do
      logger.info "Waiting for scheduler daemon pid file to show up"

      run "while ! test -f #{rubber_env.resque_scheduler_pid_file}; do sleep 1; done"
    end


  end

end
