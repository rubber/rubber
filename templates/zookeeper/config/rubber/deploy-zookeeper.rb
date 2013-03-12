
namespace :rubber do
  
  namespace :zookeeper do
    
    rubber.allow_optional_tasks(self)
    
    after "rubber:install_packages", "rubber:zookeeper:install"
  
    task :install, :roles => :zookeeper do
      rubber.sudo_script 'install_zookeeper', <<-ENDSCRIPT
        if [[ ! -d "#{rubber_env.zookeeper_install_dir}" ]]; then
          # Fetch the sources.
          wget -qNP /tmp #{rubber_env.zookeeper_package_url}
          tar -C #{File.dirname rubber_env.zookeeper_install_dir} -zxf /tmp/#{File.basename rubber_env.zookeeper_package_url}

          rm -f /tmp/#{File.basename rubber_env.zookeeper_package_url}
        fi
      ENDSCRIPT
    end

    after "rubber:bootstrap", "rubber:zookeeper:bootstrap"

    task :bootstrap, :roles => :zookeeper do
      exists = capture("echo $(ls #{rubber_env.zookeeper_data_dir} 2> /dev/null)")
      if exists.strip.size == 0
        rubber.update_code_for_bootstrap
        rubber.run_config(:file => "role/zookeeper/", :force => true, :deploy_path => release_path)

        restart
      end
    end
    
    desc <<-DESC
      Starts the zookeeper daemon
    DESC
    task :start, :roles => :zookeeper do
      rsudo "service zookeeper status || service zookeeper start"
    end
    
    desc <<-DESC
      Stops the zookeeper daemon
    DESC
    task :stop, :roles => :zookeeper do
      rsudo "service zookeeper stop || true"
    end
    
    desc <<-DESC
      Restarts the zookeeper daemon
    DESC
    task :restart, :roles => :zookeeper do
      stop
      start
    end
    
  end

end
