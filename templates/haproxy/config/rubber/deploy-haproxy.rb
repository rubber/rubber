
namespace :rubber do

  namespace :haproxy do
  
    rubber.allow_optional_tasks(self)
  
    # serial_task can only be called after roles defined - not normally a problem, but
    # rubber auto-roles don't get defined till after all tasks are defined
    on :load do
      rubber.serial_task self, :serial_restart, :roles => :haproxy do
        rsudo "service haproxy stop; service haproxy start"
      end
      rubber.serial_task self, :serial_reload, :roles => :haproxy do
        rsudo "if ! ps ax | grep -v grep | grep -c haproxy &> /dev/null; then service haproxy start; else service haproxy reload; fi"
      end
    end
    
    after "rubber:install_packages", "rubber:haproxy:custom_install"
    
    task :custom_install, :roles => :web do
      rubber.sudo_script 'install_haproxy_dev', <<-ENDSCRIPT
        
        function error_non_exit { echo "Error ignored"; }
        if [[ ! `/usr/sbin/haproxy -v 2> /dev/null` =~ "1.5-dev15" ]]; then

          trap error_non_exit ERR
          apt-get -y install haproxy
          trap error_exit ERR

          echo 'Installing HaProxy 1.5-dev15'
          cd /usr/src
          wget http://haproxy.1wt.eu/download/1.5/src/devel/haproxy-1.5-dev15.tar.gz
          tar xzf haproxy-1.5-dev15.tar.gz
          cd haproxy-1.5-dev15/
          make TARGET=linux2628 USE_STATIC_PCRE=1 USE_OPENSSL=1
          sudo make PREFIX=/usr install

        fi
      ENDSCRIPT
    end

    before "deploy:stop", "rubber:haproxy:stop"
    after "deploy:start", "rubber:haproxy:start"
    after "deploy:restart", "rubber:haproxy:reload"
    
    desc "Stops the haproxy server"
    task :stop, :roles => :haproxy do
      rsudo "service haproxy stop || true"
    end
    
    desc "Starts the haproxy server"
    task :start, :roles => :haproxy do
      rsudo "service haproxy start"
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
