
namespace :rubber do

  namespace :passenger do
  
    rubber.allow_optional_tasks(self)
  
    after "rubber:install_gems", "rubber:passenger:custom_install"
    
    task :custom_install, :roles => :passenger do
      rubber.sudo_script 'install_passenger', <<-ENDSCRIPT
        if [[ -z `ls #{rubber_env.passenger_lib} 2> /dev/null` ]]; then
          echo -en "\n\n\n\n" | passenger-install-apache2-module
        fi
      ENDSCRIPT
    end

    after "rubber:setup_app_permissions", "rubber:passenger:setup_passenger_permissions"

    task :setup_passenger_permissions, :roles => :passenger do
      rsudo "chown #{rubber_env.app_user}:#{rubber_env.app_user} #{current_path}/config/environment.rb"
    end

    # passenger depends on apache for start/stop/restart, just need these defined
    # as apache hooks into standard deploy lifecycle
    
    deploy.task :restart, :roles => :app do
    end
    
    deploy.task :stop, :roles => :app do
    end
    
    deploy.task :start, :roles => :app do
    end
    
  end
end
