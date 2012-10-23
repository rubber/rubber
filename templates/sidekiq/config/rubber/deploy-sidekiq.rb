namespace :rubber do
  namespace :sidekiq do

    rubber.allow_optional_tasks(self)

    before "deploy",        "rubber:sidekiq:quiet"
    after "deploy:stop",    "rubber:sidekiq:stop"
    after "deploy:start",   "rubber:sidekiq:start"
    after "deploy:restart", "rubber:sidekiq:restart"

    desc "Quiet sidekiq (stop accepting new work)"
    task :quiet, :roles => :sidekiq do
      rsudo "cd #{current_path} && if [ -f #{current_path}/tmp/pids/sidekiq.pid ]; then bundle exec sidekiqctl quiet #{current_path}/tmp/pids/sidekiq.pid ; fi", :as => rubber_env.app_user
    end

    desc "Stop sidekiq"
    task :stop, :roles => :sidekiq do
      # Allow workers up to 60 seconds to finish their processing.
      rsudo "cd #{current_path} && if [ -f #{current_path}/tmp/pids/sidekiq.pid ]; then bundle exec sidekiqctl stop #{current_path}/tmp/pids/sidekiq.pid 60 ; fi", :as => rubber_env.app_user
    end

    desc "Start sidekiq"
    task :start, :roles => :sidekiq do
      rsudo "cd #{current_path} ; nohup bundle exec sidekiq -e #{Rubber.env} -C #{current_path}/config/sidekiq.yml -P #{current_path}/tmp/pids/sidekiq.pid >> #{current_path}/log/sidekiq.log 2>&1 &", :pty => false, :as => rubber_env.app_user
      sleep 45 # Give the workers some time to start up before moving on so monit doesn't try to start as well.
    end

    desc "Restart sidekiq"
    task :restart, :roles => :sidekiq do
      stop
      start
    end

  end
end
