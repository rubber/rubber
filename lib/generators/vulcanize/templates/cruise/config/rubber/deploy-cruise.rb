
namespace :rubber do
  namespace :cruise do
  
    rubber.allow_optional_tasks(self)
    
    # want ssh keys to be generated before we try and print it out
    after "custom_install_base", "rubber:cruise:custom_install"

    task :custom_install, :roles => :cruise do
      rubber.sudo_script 'install_cruise', <<-ENDSCRIPT
        export CRUISE_HOME="#{rubber_env.cruise_dir}"
        
        if [[ ! -d $CRUISE_HOME ]]; then
            git clone git://github.com/sml/cruisecontrol.rb.git $CRUISE_HOME
        fi
      ENDSCRIPT
      
      logger.info("\n#######################################################################\n\n")
      logger.info("This machine needs access to your source repository for cruise control")
      logger.info("run 'cap rubber:cruise:setup_project' once access has been granted")
      logger.info("then run 'cap rubber:cruise:start' to start the cruise web server")
      logger.info("ssh public key:\n#{capture('cat ~/.ssh/id_dsa.pub')}")
      logger.info("\n#######################################################################\n\n")
   end
    
    task :setup_project, :roles => :cruise do
      rubber.sudo_script 'setup_project', <<-ENDSCRIPT
      
        export CRUISE_HOME="#{rubber_env.cruise_dir}"
        export CRUISE_DATA_ROOT="#{rubber_env.cruise_data_dir}"
        export CRUISE_PROJECT_ROOT="#{rubber_env.cruise_project_dir}"
        
        if [[ ! -d $CRUISE_HOME ]]; then
            git clone git://github.com/sml/cruisecontrol.rb.git #{rubber_env.cruise_dir}
        fi
        
        if [[ ! -d $CRUISE_PROJECT_ROOT ]]; then
          if [[ -z "#{rubber_env.cruise_repository}" ]]; then
            echo "cruise_repository must be set in rubber env"
            exit 1
          fi
          
          cd $CRUISE_HOME
          echo "Adding project repository to cruise: #{rubber_env.cruise_repository}"
          ./cruise add #{rubber_env.app_name} #{rubber_env.cruise_repository}
          mkdir -p $CRUISE_PROJECT_ROOT/log            
          cd $CRUISE_PROJECT_ROOT && rake db:create RAILS_ENV=test
        fi
        
      ENDSCRIPT
    end
    

    desc "Start cruise control daemon"
    task :start, :roles => :cruise do
      rsudo "/etc/init.d/cruise start"
    end
    
    desc "Stop cruise control daemon"
    task :stop, :roles => :cruise do
      rsudo "/etc/init.d/cruise stop; exit 0"
    end
    
    desc "Restart cruise control daemon"
    task :restart, :roles => :cruise do
      stop
      start
    end
      
  end
end
