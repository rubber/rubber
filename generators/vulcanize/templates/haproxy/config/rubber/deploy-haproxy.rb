
namespace :rubber do

  namespace :haproxy do
  
    rubber.allow_optional_tasks(self)
  
    after "rubber:install_packages", "rubber:haproxy:custom_install"
    
    task :custom_install, :roles => :haproxy do
      rubber.custom_package('http://http.us.debian.org/debian/pool/main/h/haproxy',
                            'haproxy', '1.3.15.2-1', '! -f /usr/sbin/haproxy')
    end
  
    # serial_task can only be called after roles defined - not normally a problem, but
    # rubber auto-roles don't get defined till after all tasks are defined
    on :load do
      rubber.serial_task self, :serial_restart, :roles => :haproxy do
        run "/etc/init.d/haproxy restart"
      end
      rubber.serial_task self, :serial_reload, :roles => :haproxy do
        run "/etc/init.d/haproxy reload"
      end
    end
    
    before "deploy:stop", "rubber:haproxy:stop"
    after "deploy:start", "rubber:haproxy:start"
    after "deploy:restart", "rubber:haproxy:serial_restart"
    
    desc "Stops the haproxy server"
    task :stop, :roles => :haproxy, :on_error => :continue do
      run "/etc/init.d/haproxy stop"
    end
    
    desc "Starts the haproxy server"
    task :start, :roles => :haproxy do
      run "/etc/init.d/haproxy start"
    end
    
    desc "Restarts the haproxy server"
    task :restart, :roles => :haproxy do
      serial_restart
    end
  
    desc "Reloads the haproxy web server"
    task :reload, :roles => :haproxy do
      serial_reload
    end
  
  end

end
