namespace :rubber do
  
  namespace :resque_worker do
    
    rubber.allow_optional_tasks(self)
    
    before "deploy:stop", "rubber:resque_worker:stop"
    after "deploy:start", "rubber:resque_worker:start"
    after "deploy:restart", "rubber:resque_worker:restart"
    
    desc "Starts default resque worker"
    task :start, :roles => :resque_worker do
      as = fetch(:runner, "app")
      via = fetch(:run_method, :sudo)
      
      invoke_command "sh -c 'cd #{current_path}; RAILS_ENV=#{rails_env} ./script/runner script/resque_worker_management.rb start'", :via => via, :as => as
    end

    desc "Stops default resque worker"
    task :stop, :roles => :resque_worker do
      as = fetch(:runner, "app")
      via = fetch(:run_method, :sudo)
      
      invoke_command "sh -c 'cd #{current_path}; RAILS_ENV=#{rails_env} ./script/runner script/resque_worker_management.rb stop'", :via => via, :as => as
    end

    desc "Restarts default resque worker"
    task :restart, :roles => :resque_worker do
      rubber.resque_worker.stop
      rubber.resque_worker.start
    end
  end

end
