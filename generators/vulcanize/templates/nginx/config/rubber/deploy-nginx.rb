
namespace :rubber do

  namespace :nginx do
  
    rubber.allow_optional_tasks(self)
    
    # serial_task can only be called after roles defined - not normally a problem, but
    # rubber auto-roles don't get defined till after all tasks are defined
    on :load do
      rubber.serial_task self, :serial_restart, :roles => [:web, :web_tools] do
        run "/etc/init.d/nginx restart"
      end
      rubber.serial_task self, :serial_reload, :roles => [:web, :web_tools] do
        run "if ! ps ax | grep -v grep | grep -c nginx &> /dev/null; then /etc/init.d/nginx start; else /etc/init.d/nginx reload; fi"
      end
    end
    
    before "deploy:stop", "rubber:nginx:stop"
    after "deploy:start", "rubber:nginx:start"
    after "deploy:restart", "rubber:nginx:reload"
    
    desc "Stops the nginx web server"
    task :stop, :roles => [:web, :web_tools], :on_error => :continue do
      run "/etc/init.d/nginx stop"
    end
    
    desc "Starts the nginx web server"
    task :start, :roles => [:web, :web_tools] do
      run "/etc/init.d/nginx start"
    end
    
    desc "Restarts the nginx web server"
    task :restart, :roles => [:web, :web_tools] do
      serial_restart
    end
  
    desc "Reloads the nginx web server"
    task :reload, :roles => [:web, :web_tools] do
      serial_reload
    end
  
  end

end
