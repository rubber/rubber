
namespace :rubber do

  namespace :passenger do
  
    rubber.allow_optional_tasks(self)
  
    after "rubber:install_gems", "rubber:passenger:custom_install"
    
    task :custom_install, :roles => :passenger do
      rubber.sudo_script 'install_passenger', <<-ENDSCRIPT
        # can't use passenger_lib from rubber here as it only evaluates correctly
        # when variable interpolation of rvm_gem_home is run remotely, and since we
        # are in cap, we run the interpolation locally
        #
        passenger_lib=$(find /usr/local/rvm/gems/`rvm current` -path "*/passenger-#{rubber_env.passenger_version}/*/mod_passenger.so" 2> /dev/null)
        if [[ -z $passenger_lib ]]; then
          echo -en "\n\n\n\n" | passenger-install-apache2-module
          rvm #{rubber_env.rvm_ruby} --passenger
        fi
      ENDSCRIPT
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
