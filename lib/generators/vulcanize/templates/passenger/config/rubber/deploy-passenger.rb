
namespace :rubber do

  namespace :passenger do
  
    rubber.allow_optional_tasks(self)
  
    after "rubber:install_gems", "rubber:passenger:custom_install"
    
    task :custom_install, :roles => :passenger do
      rubber.sudo_script 'install_passenger', <<-ENDSCRIPT
        if [[ -z `ls #{rubber_env.passenger_lib} 2> /dev/null` ]]; then
          echo -en "\n\n\n\n" | passenger-install-apache2-module
          rvm #{rubber_env.rvm_ruby} --passenger
        fi
      ENDSCRIPT
    end

    after "rubber:setup_app_permissions", "rubber:passenger:setup_passenger_permissions"

    task :setup_passenger_permissions, :roles => :passenger do
      rsudo "chown #{rubber_env.app_user}:#{rubber_env.app_user} #{current_path}/config/environment.rb"
    end

    # passenger does things differently for rack apps, so if this is a rails app, remove config.ru
    # to stop passenger from treating this like a rack app
    after "deploy:update_code", "rubber:passenger:remove_config_ru" if Rubber::Util.is_rails?

    task :remove_config_ru, :roles => :passenger do
      rsudo "rm -f  #{current_release}/config.ru"
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
