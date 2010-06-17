
namespace :rubber do
  
  namespace :mongrel do
    
    rubber.allow_optional_tasks(self)
    
    after "rubber:install_gems", "rubber:mongrel:custom_install"
    
    task :custom_install, :roles => :mongrel do
      # Setup system to restart mongrel_cluster on reboot
      rubber.sudo_script 'setup_mongrel_init', <<-ENDSCRIPT
        mkdir -p /etc/mongrel_cluster
        rm -f /etc/mongrel_cluster/#{application}-#{RUBBER_ENV}.yml && ln -s /mnt/#{application}-#{RUBBER_ENV}/current/config/mongrel_cluster.yml /etc/mongrel_cluster/#{application}-#{RUBBER_ENV}.yml
        find #{rubber_env.rvm_version ? "$(rvm gemdir)" : "/usr/lib/ruby/gems"} -path "*/resources/mongrel_cluster" -exec cp {} /etc/init.d/ \\;
        chmod +x /etc/init.d/mongrel_cluster
        update-rc.d -f mongrel_cluster remove
        update-rc.d mongrel_cluster defaults 99 00
      ENDSCRIPT
    end
    
    
    def mongrel_stop
        rsudo "cd #{current_path} && mongrel_rails cluster::stop"
        sleep 5 # Give the graceful stop a chance to complete
        rsudo "cd #{current_path} && mongrel_rails cluster::stop --force --clean"
    end
    
    def mongrel_start
        rsudo "cd #{current_path} && mongrel_rails cluster::start --clean"
        pid_cnt = rubber_env.mongrel_count
        logger.info "Waiting for mongrel pid files to show up"
        rsudo "while ((`ls #{current_path}/tmp/pids/mongrel.*.pid 2> /dev/null | wc -l` < #{pid_cnt})); do sleep 1; done"
    end
    
    # serial_task can only be called after roles defined - not normally a problem, but
    # rubber auto-roles don't get defined till after all tasks are defined
    on :load do
      rubber.serial_task self, :serial_restart, :roles => :mongrel do
        teardown_connections_to(sessions.keys)
        mongrel_stop
        mongrel_start
      end
    end
    
    desc "Restarts the mongrel app server"
    task :restart, :roles => :mongrel do
      serial_restart
    end
    
    desc "Stops the mongrel app server"
    task :stop, :roles => :mongrel do
      mongrel_stop
    end
    
    desc "Starts the mongrel app server"
    task :start, :roles => :mongrel do
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
