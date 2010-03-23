
namespace :rubber do

  namespace :apache do
  
    rubber.allow_optional_tasks(self)

    after "rubber:install_packages", "rubber:apache:custom_install"

    task :custom_install, :roles => :apache do
      sudo "a2dissite default"
    end

    # serial_task can only be called after roles defined - not normally a problem, but
    # rubber auto-roles don't get defined till after all tasks are defined
    on :load do
      rubber.serial_task self, :serial_restart, :roles => :apache do
        sudo "/etc/init.d/apache2 restart"
      end
      rubber.serial_task self, :serial_reload, :roles => :apache do
        sudo "sh -c 'if ! ps ax | grep -v grep | grep -c apache2 &> /dev/null; then /etc/init.d/apache2 start; else /etc/init.d/apache2 reload; fi'"
      end
    end
    
    before "deploy:stop", "rubber:apache:stop"
    after "deploy:start", "rubber:apache:start"
    after "deploy:restart", "rubber:apache:reload"
    
    desc "Stops the apache web server"
    task :stop, :roles => :apache, :on_error => :continue do
      sudo "/etc/init.d/apache2 stop"
    end
    
    desc "Starts the apache web server"
    task :start, :roles => :apache do
      sudo "/etc/init.d/apache2 start"
    end
    
    desc "Restarts the apache web server"
    task :restart, :roles => :apache do
      serial_restart
    end
  
    desc "Reloads the apache web server"
    task :reload, :roles => :apache do
      serial_reload
    end
  
  end

end
