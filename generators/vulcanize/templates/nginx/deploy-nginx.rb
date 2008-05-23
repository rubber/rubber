
namespace :rubber do

  namespace :nginx do
  
    rubber.allow_optional_tasks(self)
  
    after "rubber:install_packages", "rubber:nginx:custom_install"
    
    task :custom_install, :roles => :web do
      # install nginx+fair_proxy over the already installed nginx ubuntu package
      # this way we get all the system scripts
      if rubber_cfg.environment.bind().nginx_use_fair_proxy
        rubber.run_script 'install_nginx', <<-ENDSCRIPT
          if test -f /usr/sbin/nginx && ! strings /usr/sbin/nginx | grep -c fair > /dev/null; then
            rm -rf /tmp/*nginx*
            wget -qP /tmp http://sysoev.ru/nginx/nginx-0.5.35.tar.gz
            wget -qP /tmp http://github.com/gnosek/nginx-upstream-fair/tarball/master
            tar -C /tmp -xzf /tmp/nginx-0.5.35.tar.gz
            tar -C /tmp -xzf /tmp/*nginx-upstream-fair*.tar.gz
            rm -f /tmp/*nginx*.tar.gz
            cd /tmp/nginx-0.5.35
            ./configure --conf-path=/etc/nginx/nginx.conf \
              --error-log-path=/var/log/nginx/error.log --pid-path=/var/run/nginx.pid \
              --lock-path=/var/lock/nginx.lock   --http-log-path=/var/log/nginx/access.log \
              --http-client-body-temp-path=/var/lib/nginx/body --http-proxy-temp-path=/var/lib/nginx/proxy \
              --http-fastcgi-temp-path=/var/lib/nginx/fastcgi --with-debug --with-http_stub_status_module \
              --with-http_flv_module --with-http_ssl_module --with-http_dav_module \
              --prefix=/usr --add-module=/tmp/*nginx-upstream-fair*
            make
            test ! -f '/usr/sbin/nginx' || mv '/usr/sbin/nginx' '/usr/sbin/nginx.old'
            ! killall nginx
            cp -f objs/nginx /usr/sbin/nginx
          fi
        ENDSCRIPT
      end
    end
  
    # serial_task can only be called after roles defined - not normally a problem, but
    # rubber auto-roles don't get defined till after all tasks are defined
    on :load do
      rubber.serial_task self, :serial_restart, :roles => :web do
        run "/etc/init.d/nginx restart"
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
    
    desc "Retarts the nginx web server"
    task :restart, :roles => :web do
      serial_restart
    end
  
  end

end
