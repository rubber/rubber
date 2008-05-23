
namespace :rubber do
    namespace :mongrel do
    
    rubber.allow_optional_tasks(self)
    
    after "rubber:install_gems", "rubber:mongrel:custom_install"
    
    task :custom_install, :roles => :app do
      # Setup system to restart mongrel_cluster on reboot
      rubber.sudo_script 'install_app', <<-ENDSCRIPT
        mkdir -p /etc/mongrel_cluster
        rm -f /etc/mongrel_cluster/#{application}-#{rails_env}.yml && ln -s /mnt/#{application}-#{rails_env}/current/config/mongrel_cluster.yml /etc/mongrel_cluster/#{application}-#{rails_env}.yml
        find /usr/lib/ruby/gems -path "*/resources/mongrel_cluster" -exec cp {} /etc/init.d/ \\;
        chmod +x /etc/init.d/mongrel_cluster
        update-rc.d -f mongrel_cluster remove
        update-rc.d mongrel_cluster defaults 99 00
      ENDSCRIPT
    end
    
    
    def mongrel_stop
        run "cd #{current_path} && mongrel_rails cluster::stop"
        sleep 5 # Give the graceful stop a chance to complete
        run "cd #{current_path} && mongrel_rails cluster::stop --force --clean"
    end
    
    def mongrel_start
        run "cd #{current_path} && mongrel_rails cluster::start --clean"
        pid_cnt = rubber_cfg.environment.bind().appserver_count
        logger.info "Waiting for mongrel pid files to show up"
        run "while ((`ls #{current_path}/tmp/pids/mongrel.*.pid 2> /dev/null | wc -l` < #{pid_cnt})); do sleep 1; done"
    end
    
    # serial_task can only be called after roles defined - not normally a problem, but
    # rubber auto-roles don't get defined till after all tasks are defined
    on :load do
      rubber.serial_task self, :serial_restart, :roles => :app do
        mongrel_stop
        mongrel_start
      end
    end
    
    desc "Restarts the mongrel app server"
    task :restart, :roles => :app do
      serial_restart
    end
    
    desc "Stops the mongrel app server"
    task :stop, :roles => :app do
      mongrel_stop
    end
    
    desc "Starts the mongrel app server"
    task :start, :roles => :app do
      mongrel_start
    end
    
    deploy.task :restart, :roles => :app do
      rubber.mongrel.restart
    end
    
    deploy.task :stop, :roles => :app do
      rubber.mongrel.stop
    end
    
    deploy.task :start, :roles => :app do
      rubber.mongrel.start
    end
  
  end
  
end
