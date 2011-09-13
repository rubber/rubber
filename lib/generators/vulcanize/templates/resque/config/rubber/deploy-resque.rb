
namespace :rubber do

  namespace :resque do
  
    rubber.allow_optional_tasks(self)

    namespace :worker do

      rubber.allow_optional_tasks(self)

      before "deploy:stop", "rubber:resque:worker:stop"
      after "deploy:start", "rubber:resque:worker:start"
      after "deploy:restart", "rubber:resque:worker:restart"

      desc "Starts resque workers"
      task :start, :roles => :resque_worker do
        rsudo "cd #{current_path} && RUBBER_ENV=#{rails_env} ./script/resque_worker_management.rb start", :as => rubber_env.app_user
      end

      desc "Stops resque workers"
      task :stop, :roles => :resque_worker do
        rsudo "cd #{current_path} && RUBBER_ENV=#{rails_env} ./script/resque_worker_management.rb stop", :as => rubber_env.app_user
      end

      desc "Restarts resque workers"
      task :restart, :roles => :resque_worker do
        rsudo "cd #{current_path} && RUBBER_ENV=#{rails_env} ./script/resque_worker_management.rb restart", :as => rubber_env.app_user
      end

      # pauses deploy until all workers up so monit doesn't try and start them
      before "rubber:monit:start", "rubber:resque:worker:wait_start"
      task :wait_start, :roles => :resque_worker do
        logger.info "Waiting for resque worker pid files to show up"

        opts = get_host_options('resque_workers') do |worker_cfg|
          worker_cfg.size.to_s
        end

        run "while ((`ls #{current_path}/tmp/pids/resque_worker_*.pid 2> /dev/null | wc -l` < $CAPISTRANO:VAR$)); do sleep 1; done", opts
      end
      
    end

    namespace :web do
      rubber.allow_optional_tasks(self)

      before "deploy:stop", "rubber:resque:web:stop"
      after "deploy:start", "rubber:resque:web:start"
      after "deploy:restart", "rubber:resque:web:restart"

      desc "Starts resque web tools"
      task :start, :roles => :resque_web do
        rsudo "RAILS_ENV=#{RUBBER_ENV} resque-web --pid-file #{Rubber.root}/tmp/pids/resque_web.pid --port #{rubber_env.resque_web_port} --no-launch #{current_path}/config/initializers/resque.rb", :as => rubber_env.app_user
      end

      desc "Stops resque web tools"
      task :stop, :roles => :resque_web do
        rsudo "RAILS_ENV=#{RUBBER_ENV} resque-web --pid-file #{Rubber.root}/tmp/pids/resque_web.pid --kill", :as => rubber_env.app_user
      end

      desc "Restarts resque web tools"
      task :restart, :roles => :resque_web do
        rubber.resque.web.stop
        rubber.resque.web.start
      end

    end

  end
end
