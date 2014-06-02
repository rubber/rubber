namespace :rubber do

  namespace :passenger_nginx do
  
    rubber.allow_optional_tasks(self)
  
    before "rubber:install_packages", "rubber:passenger_nginx:setup_apt_sources"
    task :setup_apt_sources do
      rubber.sudo_script 'configure_passenger_nginx_repository', <<-ENDSCRIPT
        apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 561F9B9CAC40B2F7
        add-apt-repository -y https://oss-binaries.phusionpassenger.com/apt/passenger
      ENDSCRIPT
    end
  
    after "rubber:setup_app_permissions", "rubber:passenger_nginx:setup_passenger_permissions"

    task :setup_passenger_permissions, :roles => :passenger_nginx do
      rsudo "chown #{rubber_env.app_user}:#{rubber_env.app_user} #{current_path}/config/environment.rb"
    end
    
    on :load do
      rubber.serial_task self, :serial_restart, :roles => :passenger_nginx do
        rsudo "service nginx restart"
      end
      rubber.serial_task self, :serial_reload, :roles => :passenger_nginx do
        rsudo "if ! ps ax | grep -v grep | grep -c nginx &> /dev/null; then service nginx start; else service nginx reload; fi"
      end
    end

    before "deploy:stop", "rubber:passenger_nginx:stop"
    after "deploy:start", "rubber:passenger_nginx:start"
    after "deploy:restart", "rubber:passenger_nginx:reload"
    
    desc "Stops the nginx web server"
    task :stop, :roles => :passenger_nginx do
      rsudo "service nginx stop; exit 0"
    end
    
    desc "Starts the nginx web server"
    task :start, :roles => :passenger_nginx do
      rsudo "service nginx status || service nginx start"
    end
    
    desc "Restarts the nginx web server"
    task :restart, :roles => :passenger_nginx do
      serial_restart
    end
  
    desc "Reloads the nginx web server"
    task :reload, :roles => :passenger_nginx do
      serial_reload
    end
    
  end
end
