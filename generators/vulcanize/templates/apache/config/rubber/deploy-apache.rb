
namespace :rubber do

  namespace :apache do
  
    rubber.allow_optional_tasks(self)
  
    # serial_task can only be called after roles defined - not normally a problem, but
    # rubber auto-roles don't get defined till after all tasks are defined
    on :load do
      rubber.serial_task self, :serial_restart, :roles => :web do
        run "/etc/init.d/apache2 restart"
      end
      rubber.serial_task self, :serial_reload, :roles => :web do
        run "if ! ps ax | grep -v grep | grep -c apache2 &> /dev/null; then /etc/init.d/apache2 start; else /etc/init.d/apache2 reload; fi"
      end
    end
    
    before "deploy:stop", "rubber:apache:stop"
    after "deploy:start", "rubber:apache:start"
    after "deploy:restart", "rubber:apache:reload"
    
    desc "Stops the apache web server"
    task :stop, :roles => :web, :on_error => :continue do
      run "/etc/init.d/apache2 stop"
    end
    
    desc "Starts the apache web server"
    task :start, :roles => :web do
      run "/etc/init.d/apache2 start"
    end
    
    desc "Restarts the apache web server"
    task :restart, :roles => :web do
      serial_restart
    end
  
    desc "Reloads the apache web server"
    task :reload, :roles => :web do
      serial_reload
    end
  
  end

end
