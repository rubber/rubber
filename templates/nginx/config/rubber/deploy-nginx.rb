
namespace :rubber do

  namespace :nginx do
    
    rubber.allow_optional_tasks(self)
    
    before "rubber:install_packages", "rubber:nginx:install"
    
    task :install, :roles => :nginx do
      # Setup apt sources for current nginx
      sources = <<-SOURCES
        deb http://nginx.org/packages/ubuntu/ lucid nginx
        deb-src http://nginx.org/packages/ubuntu/ lucid nginx
      SOURCES
      sources.gsub!(/^ */, '')
      put(sources, "/etc/apt/sources.list.d/nginx.list")
      rsudo "wget -qO- http://nginx.org/keys/nginx_signing.key | apt-key add -"  
    end
    
    # serial_task can only be called after roles defined - not normally a problem, but
    # rubber auto-roles don't get defined till after all tasks are defined
    on :load do
      rubber.serial_task self, :serial_restart, :roles => :nginx do
        rsudo service_restart('nginx')
      end
      rubber.serial_task self, :serial_reload, :roles => :nginx do
        rsudo "if ! ps ax | grep -v grep | grep -c nginx &> /dev/null; then #{service_start('nginx')}; else #{service_reload('nginx')}; fi"
      end
    end
    
    before "deploy:stop", "rubber:nginx:stop"
    after "deploy:start", "rubber:nginx:start"
    after "deploy:restart", "rubber:nginx:reload"
    
    desc "Stops the nginx web server"
    task :stop, :roles => :nginx do
      rsudo "#{service_stop('nginx')}; exit 0"
    end
    
    desc "Starts the nginx web server"
    task :start, :roles => :nginx do
      rsudo "#{service_status('nginx')} || #{service_start('nginx')}"
    end
    
    desc "Restarts the nginx web server"
    task :restart, :roles => :nginx do
      serial_restart
    end
  
    desc "Reloads the nginx web server"
    task :reload, :roles => :nginx do
      serial_reload
    end

    desc "Display status of the nginx web server"
    task :status, :roles => :nginx do
      rsudo "#{service_status('nginx')} || true"
      rsudo "ps -eopid,user,fname | grep [n]ginx || true"
      rsudo "netstat -tulpn | grep nginx || true"
    end

  end

end
