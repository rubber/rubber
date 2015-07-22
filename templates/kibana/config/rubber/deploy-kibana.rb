namespace :rubber do

  namespace :kibana do

    rubber.allow_optional_tasks(self)

    after "rubber:install_packages", "rubber:kibana:install"

    task :install, :roles => :kibana do
      rubber.sudo_script 'install_kibana', <<-ENDSCRIPT
        if [[ ! -d "#{rubber_env.kibana_dir}" ]]; then
          wget --no-check-certificate -qNP /tmp #{rubber_env.kibana_package_url}
          tar -C #{rubber_env.kibana_prefix} -xzf /tmp/kibana-#{rubber_env.kibana_version}-linux-x64.tar.gz
          rm /tmp/kibana-#{rubber_env.kibana_version}-linux-x64.tar.gz
        fi
      ENDSCRIPT
    end

    after "rubber:bootstrap", "rubber:kibana:bootstrap"

    task :bootstrap, :roles => :kibana do
      exists = capture("echo $(ls /etc/init/kibana.conf 2> /dev/null)")
      if exists.strip.size == 0
        rubber.update_code_for_bootstrap
        rubber.run_config(:file => "role/kibana/", :force => true, :deploy_path => release_path)

        restart
      end
    end

    task :start, :roles => :kibana do
      rsudo "service kibana start"
    end

    task :stop, :roles => :kibana do
      rsudo "service kibana stop || true"
    end

    task :restart, :roles => :kibana do
      stop
      start
    end

  end
end
