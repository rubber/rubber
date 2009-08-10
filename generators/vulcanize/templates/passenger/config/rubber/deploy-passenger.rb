
namespace :rubber do

  namespace :passenger do
  
    rubber.allow_optional_tasks(self)
  
    #before "rubber:install_gems", "rubber:passenger:install_enterprise_ruby"
    after "rubber:install_gems", "rubber:passenger:custom_install"
    
    task :custom_install, :roles => :web do
      #if [[ ! -f /opt/ruby-enterprise/lib/ruby/gems/1.8/gems/passenger-2.2.4/ext/apache2/mod_passenger.so ]]; then
      rubber.sudo_script 'install_passenger', <<-ENDSCRIPT      
        echo -en "\n\n\n\n" | passenger-install-apache2-module
        # disable ubuntu default site
        a2dissite default
      ENDSCRIPT
    end
    
    task :install_enterprise_ruby, :roles => :web do
      rubber.sudo_script 'install_enterprise_ruby', <<-ENDSCRIPT
        if [[ ! -d /opt/ruby-enterprise ]]; then
          wget -q http://rubyforge.org/frs/download.php/58679/ruby-enterprise_1.8.6-20090610_i386.deb
          dpkg -i ruby-enterprise_1.8.6-20090610_i386.deb
          echo "export PATH=/opt/ruby-enterprise/bin:$PATH" >> /etc/environment
        fi
      ENDSCRIPT
      
      # Force Capistrano to reconnect and load our new environment
      teardown_connections_to(sessions.keys)
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
