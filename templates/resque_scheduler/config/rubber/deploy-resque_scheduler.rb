namespace :rubber do

  namespace :resque_scheduler do

    rubber.allow_optional_tasks(self)

    before "deploy:stop", "rubber:resque_scheduler:stop"
    after "deploy:start", "rubber:resque_scheduler:start"
    after "deploy:restart", "rubber:resque_scheduler:restart"
    
    desc "Stops the resque_scheduler"
    task :stop, :roles => :resque_scheduler do
      rsudo "#{service_stop('resque-scheduler')} || true"
    end

    desc "Starts the resque_scheduler"
    task :start, :roles => :resque_scheduler do
      rsudo "#{service_start('resque-scheduler')} || true"
    end

    desc "Restarts the resque_scheduler"
    task :restart, :roles => :resque_scheduler do
      stop
      start      
    end

    after "rubber:bootstrap", "rubber:resque_scheduler:bootstrap"

    task :bootstrap, :roles => :resque_scheduler do
      log_dir = File.dirname(rubber_env.resque_scheduler_log_file)

      exists = capture("echo $(ls #{log_dir} 2> /dev/null)")
      if exists.strip.size == 0
        rubber.sudo_script 'bootstrap_resque_scheduler', <<-ENDSCRIPT
          if [ ! -d #{log_dir} ]; then
            mkdir -p #{log_dir}
            chown #{rubber_env.app_user}:#{rubber_env.app_user} #{log_dir}
          fi
        ENDSCRIPT
      end
    end

    # pauses deploy until daemon is up so monit doesn't try and start it
    before "rubber:monit:start", "rubber:resque_scheduler:wait_start"
    task :wait_start, :roles => :resque_scheduler do
      logger.info "Waiting for scheduler daemon pid file to show up"

      run "while ! test -f #{rubber_env.resque_scheduler_pid_file}; do sleep 1; done"
    end


  end

end
