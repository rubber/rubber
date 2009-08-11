
namespace :rubber do

  namespace :passenger do
  
    rubber.allow_optional_tasks(self)
  
    after "rubber:install_gems", "rubber:passenger:custom_install"
    
    task :custom_install, :roles => :web do
      rubber.sudo_script 'install_passenger', <<-ENDSCRIPT
        if [[ ! -f /usr/lib/ruby/gems/*/gems/passenger-*/ext/apache2/mod_passenger.so ]]; then
          echo -en "\n\n\n\n" | passenger-install-apache2-module
          # disable ubuntu default site
          a2dissite default
        fi
      ENDSCRIPT
    end  
    
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
    
    deploy.task :restart, :roles => :web do
      rubber.passenger.restart
    end
    
    deploy.task :stop, :roles => :web do
      rubber.passenger.stop
    end
    
    deploy.task :start, :roles => :web do
      rubber.passenger.start
    end
    
  end
end
