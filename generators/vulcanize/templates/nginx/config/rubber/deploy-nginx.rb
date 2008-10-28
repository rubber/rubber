
namespace :rubber do

  namespace :nginx do
  
    rubber.allow_optional_tasks(self)
  
    after "rubber:install_packages", "rubber:nginx:custom_install"
    
    task :custom_install, :roles => :web do
      rubber.custom_package('http://ppa.launchpad.net/calmkelp/ubuntu/pool/main/n/nginx',
                            'nginx', '0.6.32-1ubuntu1.3~ppa2', '! -f /usr/sbin/nginx')
    end  
  
    # serial_task can only be called after roles defined - not normally a problem, but
    # rubber auto-roles don't get defined till after all tasks are defined
    on :load do
      rubber.serial_task self, :serial_restart, :roles => :web do
        run "/etc/init.d/nginx restart"
      end
      rubber.serial_task self, :serial_reload, :roles => :web do
        run "/etc/init.d/nginx reload"
      end
    end
    
    before "deploy:stop", "rubber:nginx:stop"
    after "deploy:start", "rubber:nginx:start"
    after "deploy:restart", "rubber:nginx:serial_restart"
    
    desc "Stops the nginx web server"
    task :stop, :roles => :web, :on_error => :continue do
      run "/etc/init.d/nginx stop"
    end
    
    desc "Starts the nginx web server"
    task :start, :roles => :web do
      run "/etc/init.d/nginx start"
    end
    
    desc "Restarts the nginx web server"
    task :restart, :roles => :web do
      serial_restart
    end
  
    desc "Reloads the nginx web server"
    task :reload, :roles => :web do
      serial_reload
    end
  
  end

end
