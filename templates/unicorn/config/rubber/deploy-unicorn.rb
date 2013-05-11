
namespace :rubber do

  namespace :unicorn do
  
    rubber.allow_optional_tasks(self)
    
    before "deploy:stop", "rubber:unicorn:stop"
    after "deploy:start", "rubber:unicorn:start"
    after "deploy:restart", "rubber:unicorn:reload"
    
    desc "Stops the unicorn server"
    task :stop, :roles => :unicorn do
      rsudo "if [ -f /var/run/unicorn.pid ]; then pid=`cat /var/run/unicorn.pid` && kill -TERM $pid; fi"
    end
    
    desc "Starts the unicorn server"
    task :start, :roles => :unicorn do
      rsudo "cd #{current_path} && bundle exec unicorn_rails -c #{current_path}/config/unicorn.rb -E #{Rubber.env} -D"
    end
    
    desc "Restarts the unicorn server"
    task :restart, :roles => :unicorn do
      stop
      start
    end
  
    desc "Reloads the unicorn web server"
    task :reload, :roles => :unicorn do
      rsudo "if [ -f /var/run/unicorn.pid ]; then pid=`cat /var/run/unicorn.pid` && kill -USR2 $pid; else cd #{current_path} && bundle exec unicorn_rails -c #{current_path}/config/unicorn.rb -E #{Rubber.env} -D; fi"
    end

    desc "Display status of the unicorn web server"
    task :status, :roles => :unicorn do
      # "service unicorn status" always returns "unicorn stop/waiting"
      rsudo "ps -eopid,user,cmd | grep [u]nicorn || true"
      rsudo "netstat -tupan | grep unicorn || true"
    end

  end

end
