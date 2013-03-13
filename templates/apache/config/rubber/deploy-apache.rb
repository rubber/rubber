
namespace :rubber do

  namespace :apache do
  
    rubber.allow_optional_tasks(self)

    after "rubber:install_packages", "rubber:apache:install"

    task :install, :roles => :apache do
      rubber.sudo_script 'install_apache', <<-ENDSCRIPT
        a2dissite default

        # TODO: remove this once 12.04 is fixed
        # https://bugs.launchpad.net/ubuntu/+source/mod-proxy-html/+bug/964397
        if [[ ! -f /usr/lib/libxml2.so.2 ]]; then
          ln -sf /usr/lib/x86_64-linux-gnu/libxml2.so.2 /usr/lib/libxml2.so.2
        fi
      ENDSCRIPT
    end
    
    after "rubber:bootstrap", "rubber:apache:bootstrap"

    task :bootstrap, :roles => :apache do
      exists = capture("grep 'empty ports file' /etc/apache2/ports.conf || true")
      if exists.strip.size == 0
        rubber.update_code_for_bootstrap
        rubber.run_config(:file => "role/apache", :force => true, :deploy_path => release_path)
      end
    end
    

    # serial_task can only be called after roles defined - not normally a problem, but
    # rubber auto-roles don't get defined till after all tasks are defined
    on :load do
      rubber.serial_task self, :serial_restart, :roles => [:app, :apache] do
        rsudo "service apache2 stop; service apache2 start"
      end
      rubber.serial_task self, :serial_reload, :roles => [:app, :apache] do
        rsudo "if ! ps ax | grep -v grep | grep -c apache2 &> /dev/null; then service apache2 start; else service apache2 reload; fi"
      end
    end
    
    before "deploy:stop", "rubber:apache:stop"
    after "deploy:start", "rubber:apache:start"
    after "deploy:restart", "rubber:apache:reload"
    
    desc "Stops the apache web server"
    task :stop, :roles => :apache do
      rsudo "service apache2 stop || true"
    end
    
    desc "Starts the apache web server"
    task :start, :roles => :apache do
      rsudo "service apache2 status || service apache2 start"
    end
    
    desc "Restarts the apache web server"
    task :restart, :roles => :apache do
      serial_restart
    end
  
    desc "Reloads the apache web server"
    task :reload, :roles => :apache do
      serial_reload
    end
  
  end

end
