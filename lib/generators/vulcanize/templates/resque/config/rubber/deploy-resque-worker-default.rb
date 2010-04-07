namespace :rubber do
  
  namespace :resque_worker_default do
    
    rubber.allow_optional_tasks(self)
    
    before "deploy:stop", "rubber:resque_worker_default:stop"
    after "deploy:start", "rubber:resque_worker_default:start"
    after "deploy:restart", "rubber:resque_worker_default:restart"
    
    desc "Starts default resque worker"
    task :start, :roles => :resque_worker_default do
      as = fetch(:runner, "app")
      via = fetch(:run_method, :sudo)
      rubber_env.resque_worker_default_count.times do |i|
        invoke_command "sh -c 'cd #{current_path}; RAILS_ENV=#{rails_env} QUEUE=* nohup rake resque:work &> log/resque_worker_default_#{i}.log & echo $! > tmp/pids/resque_worker_default_#{i}.pid'", :via => via, :as => as
      end
    end

    desc "Stops default resque worker"
    task :stop, :roles => :resque_worker_default do
      as = fetch(:runner, "app")
      via = fetch(:run_method, :sudo)
      rubber_env.resque_worker_default_count.times do |i|
        invoke_command "sh -c 'cd #{current_path} && kill `cat tmp/pids/resque_worker_default_#{i}.pid` && rm -f tmp/pids/resque_worker_default_#{i}.pid; exit 0;'", :via => via, :as => as
      end

      sleep 11 #wait for process to finish
    end

    desc "Restarts default resque worker"
    task :restart, :roles => :resque_worker_default do
      rubber.resque_worker_default.stop
      rubber.resque_worker_default.start
    end
  end

end
