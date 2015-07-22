namespace :rubber do

  namespace :influxdb do

    rubber.allow_optional_tasks(self)

    after "rubber:install_packages", "rubber:influxdb:install"

    task :install, :roles => :influxdb do
      rubber.sudo_script 'install_influxdb', <<-ENDSCRIPT
        if ! dpkg -s influxdb &> /dev/null; then
          wget -qNP /tmp #{rubber_env.influxdb_package_url}
          dpkg -i /tmp/#{File.basename(rubber_env.influxdb_package_url)}
        fi
      ENDSCRIPT
    end

    after "rubber:bootstrap", "rubber:influxdb:bootstrap"

    task :bootstrap, :roles => :influxdb do
      exists = capture("echo $(ls #{rubber_env.influxdb_data_dir} 2> /dev/null)")
      if exists.strip.size == 0
        rubber.update_code_for_bootstrap
        rubber.run_config(:file => "role/influxdb/", :force => true, :deploy_path => release_path)

        restart
      end
    end

    task :start, :roles => :influxdb do
      rsudo "service influxdb start"
    end

    task :stop, :roles => :influxdb do
      rsudo "service influxdb stop || true"
    end

    task :restart, :roles => :influxdb do
      stop
      start
    end

  end
end
