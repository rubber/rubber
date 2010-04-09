
namespace :rubber do

  namespace :nginx do
  
    rubber.allow_optional_tasks(self)
    
    # serial_task can only be called after roles defined - not normally a problem, but
    # rubber auto-roles don't get defined till after all tasks are defined
    on :load do
      rubber.serial_task self, :serial_restart, :roles => :nginx do
        rsudo "/etc/init.d/nginx restart"
      end
      rubber.serial_task self, :serial_reload, :roles => :nginx do
        rsudo "if ! ps ax | grep -v grep | grep -c nginx &> /dev/null; then /etc/init.d/nginx start; else /etc/init.d/nginx reload; fi"
      end
    end
    
    before "deploy:stop", "rubber:nginx:stop"
    after "deploy:start", "rubber:nginx:start"
    after "deploy:restart", "rubber:nginx:reload"
    
    desc "Stops the nginx web server"
    task :stop, :roles => :nginx, :on_error => :continue do
      rsudo "/etc/init.d/nginx stop"
    end
    
    desc "Starts the nginx web server"
    task :start, :roles => :nginx do
      rsudo "/etc/init.d/nginx start"
    end
    
    desc "Restarts the nginx web server"
    task :restart, :roles => :nginx do
      serial_restart
    end
  
    desc "Reloads the nginx web server"
    task :reload, :roles => :nginx do
      serial_reload
    end
  
  end

end
