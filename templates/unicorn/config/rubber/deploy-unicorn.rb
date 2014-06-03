
namespace :rubber do

  namespace :unicorn do

    rubber.allow_optional_tasks(self)

    before "deploy:stop", "rubber:unicorn:stop"
    after "deploy:start", "rubber:unicorn:start"
    after "deploy:restart", "rubber:unicorn:upgrade"

    desc "Stops the unicorn server"
    task :stop, :roles => :unicorn do
      rsudo "service unicorn stop"
    end

    desc "Starts the unicorn server"
    task :start, :roles => :unicorn do
      rsudo "service unicorn start"
    end

    desc "Restarts the unicorn server"
    task :restart, :roles => :unicorn do
      rsudo "service unicorn restart"
    end

    desc "Reloads the unicorn web server"
    task :upgrade, :roles => :unicorn do
      rsudo "service unicorn upgrade"
    end

    desc "Forcefully kills the unicorn server"
    task :kill, :roles => :unicorn do
      rsudo "service unicorn kill"
    end

    desc "Display status of the unicorn web server"
    task :status, :roles => :unicorn do
      rsudo "service unicorn status || true"
      rsudo "ps -eopid,user,cmd | grep [u]nicorn || true"
      # rsudo "netstat -tupan | grep unicorn || true"
    end

  end

end
