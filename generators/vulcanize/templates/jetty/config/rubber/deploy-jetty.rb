
namespace :rubber do

  namespace :jetty do
  
    rubber.allow_optional_tasks(self)
  
    after "rubber:install_packages", "rubber:jetty:custom_install"
    
    task :custom_install, :roles => :jetty do
      rubber.sudo_script 'install_jetty', <<-ENDSCRIPT
        if [[ -z `ls #{rubber_env.jetty_dir} 2> /dev/null` ]]; then
          wget -q http://ftp.osuosl.org/pub/eclipse/jetty/#{rubber_env.jetty_version}/dist/jetty-distribution-#{rubber_env.jetty_version}.tar.gz
          tar -zxf jetty-distribution-#{rubber_env.jetty_version}.tar.gz
          
          # Install to appropriate location.
          mv jetty-distribution-#{rubber_env.jetty_version} #{rubber_env.jetty_prefix}
          ln -s #{rubber_env.jetty_prefix}/jetty-distribution-#{rubber_env.jetty_version} #{rubber_env.jetty_dir}
          chmod 744 #{rubber_env.jetty_dir}/bin/*.sh
          
          # Cleanup the jetty distribution
          rm #{rubber_env.jetty_dir}/webapps/*
          rm -r #{rubber_env.jetty_dir}/contexts/test.d/
          mv #{rubber_env.jetty_dir}/contexts/demo.xml #{rubber_env.jetty_dir}/contexts/demo.xml.example
          mv #{rubber_env.jetty_dir}/contexts/javadoc.xml #{rubber_env.jetty_dir}/contexts/javadoc.xml.example
          
          # Cleanup after ourselves.
          rm jetty-distribution-#{rubber_env.jetty_version}.tar.gz
        fi
      ENDSCRIPT
    end

    after "rubber:setup_app_permissions", "rubber:jetty:setup_jetty_permissions"

    task :setup_jetty_permissions, :roles => :jetty do
      run "chown -R #{rubber_env.app_user}:#{rubber_env.app_user} #{rubber_env.jetty_dir}"
    end
    
    before "deploy:stop", "rubber:jetty:stop"
    after "deploy:start", "rubber:jetty:start"
    after "deploy:restart", "rubber:jetty:restart"
    
    task :restart, :roles => :jetty do
      run "#{rubber_env.jetty_dir}/bin/jetty.sh restart"
    end
    
    task :stop, :roles => :jetty do
      run "#{rubber_env.jetty_dir}/bin/jetty.sh stop"
    end
    
    task :start, :roles => :jetty do
      run "#{rubber_env.jetty_dir}/bin/jetty.sh start"
    end
    
  end
end
