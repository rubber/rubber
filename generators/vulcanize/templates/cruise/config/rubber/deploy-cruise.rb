
namespace :rubber do
  namespace :cruise do
  
    rubber.allow_optional_tasks(self)
    
    
    after "rubber:install_gems", "rubber:cruise:custom_install"
    
    task :custom_install, :roles => :cruise do
      env = rubber_cfg.environment.bind()      
      rubber.sudo_script 'install_cruise', <<-ENDSCRIPT
      
        export CRUISE_HOME="#{env.cruise_dir}"
        export CRUISE_DATA_ROOT="$HOME/.cruise"
        export CRUISE_PROJECT_ROOT="$CRUISE_DATA_ROOT/projects/#{env.app_name}/work"
        
        if [[ ! -d $CRUISE_HOME ]]; then
            git clone git://github.com/sml/cruisecontrol.rb.git #{env.cruise_dir}
        fi
        
        if [[ ! -d $CRUISE_PROJECT_ROOT ]]; then
          if [[ -z "#{env.cruise_repository}" ]]; then
            echo "cruise_repository must be set in rubber env"
            exit 1
          fi
          
          cd $CRUISE_HOME
          echo "If the following command fails, add this ssh key to your git access list"
          cat ~/.ssh/id_dsa.pub
          echo "Adding projectrepository to cruise: #{env.cruise_repository}"
          ./cruise add #{env.app_name} #{env.cruise_repository}
          mkdir -p $CRUISE_PROJECT_ROOT/log            
          cd $CRUISE_PROJECT_ROOT && rake db:create RAILS_ENV=test
        fi
        
      ENDSCRIPT
    end
    

    desc "Start cruise control daemon"
    task :start do
      run "/etc/init.d/cruisecontrolrb start"
    end
    
    desc "Stop cruise control daemon"
    task :stop, :on_error => :continue do
      run "/etc/init.d/cruisecontrolrb stop"
    end
    
    desc "Restart cruise control daemon"
    task :restart do
      stop
      start
    end
      
  end
end
