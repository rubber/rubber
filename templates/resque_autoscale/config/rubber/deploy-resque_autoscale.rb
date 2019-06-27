
namespace :rubber do

  namespace :resque_autoscale do

    rubber.allow_optional_tasks(self)


    namespace :web do
      rubber.allow_optional_tasks(self)

      before "deploy:stop", "rubber:resque_autoscale:web:stop"
      after "deploy:start", "rubber:resque_autoscale:web:start"
      after "deploy:restart", "rubber:resque_autoscale:web:restart"

      desc "Starts resque_autoscale web tools"
      task :start, :roles => :resque_autoscale do
        rsudo "service resque-autoscale-web start"
      end

      desc "Stops resque_autoscale web tools"
      task :stop, :roles => :resque_autoscale do
        rsudo "service resque-autoscale-web stop || true"
      end

      desc "Restarts resque_autoscale web tools"
      task :restart, :roles => :resque_autoscale do
        stop
        start
      end

    end

  end
end
