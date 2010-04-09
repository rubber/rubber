
namespace :rubber do

  namespace :jetty do
  
    rubber.allow_optional_tasks(self)
  
    after "rubber:install_packages", "rubber:jetty:custom_install"
    
    task :custom_install, :roles => :jetty do
      rubber.sudo_script 'install_jetty', <<-ENDSCRIPT
        if [[ -z `ls #{rubber_env.jetty_prefix}/jetty-hightide-#{rubber_env.jetty_version} 2> /dev/null` ]]; then
          wget -qN http://dist.codehaus.org/jetty/jetty-hightide-7.0.0/jetty-hightide-#{rubber_env.jetty_version}.tar.gz
          tar -zxf jetty-hightide-#{rubber_env.jetty_version}.tar.gz
          
          # Install to appropriate location.
          mv jetty-hightide-#{rubber_env.jetty_version} #{rubber_env.jetty_prefix}
          rm -f #{rubber_env.jetty_dir}
          ln -s #{rubber_env.jetty_prefix}/jetty-hightide-#{rubber_env.jetty_version} #{rubber_env.jetty_dir}
          chmod 744 #{rubber_env.jetty_dir}/bin/*.sh
          
          # Cleanup the jetty distribution
          rm -r #{rubber_env.jetty_dir}/webapps/*
          rm -r #{rubber_env.jetty_dir}/contexts/test.d/

          for file in #{rubber_env.jetty_dir}/contexts/*.xml; do
            mv $file $file.example
          done

          # Cleanup after ourselves.
          rm jetty-hightide-#{rubber_env.jetty_version}.tar.gz
        fi
      ENDSCRIPT
    end

    after "rubber:setup_app_permissions", "rubber:jetty:setup_jetty_permissions"

    task :setup_jetty_permissions, :roles => :jetty do
      rsudo "chown -R #{rubber_env.app_user}:#{rubber_env.app_user} #{rubber_env.jetty_dir}"
    end
    
    before "deploy:stop", "rubber:jetty:stop"
    after "deploy:start", "rubber:jetty:start"
    after "deploy:restart", "rubber:jetty:restart"
    
    task :restart, :roles => :jetty do
      rsudo "#{rubber_env.jetty_dir}/bin/jetty.sh restart"
    end
    
    task :stop, :roles => :jetty do
      rsudo "#{rubber_env.jetty_dir}/bin/jetty.sh stop"
    end
    
    task :start, :roles => :jetty do
      rsudo "#{rubber_env.jetty_dir}/bin/jetty.sh start"
    end
    
  end
end
