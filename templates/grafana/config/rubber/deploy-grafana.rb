namespace :rubber do

  namespace :grafana do

    rubber.allow_optional_tasks(self)

    after "rubber:install_packages", "rubber:grafana:install"

    task :install, :roles => :grafana do
      rubber.sudo_script 'install_grafana', <<-ENDSCRIPT
        if ! dpkg -s grafana &> /dev/null; then
          wget -qNP /tmp #{rubber_env.grafana_package_url}
          dpkg -i /tmp/#{File.basename(rubber_env.grafana_package_url)}
        fi
      ENDSCRIPT
    end

    # Uncomment below (and in rubber-grafana.yml), and remove above once
    # grafana 2.1 with influxdb 0.9 support is released,  using latest dev
    # version for now
    #
    # before "rubber:install_packages", "rubber:grafana:setup_apt_sources"
    #
    # task :setup_apt_sources, :roles => :grafana do
    #   rubber.sudo_script 'setup_grafana_apt', <<-ENDSCRIPT
    #     if [[ ! -f /etc/apt/sources.list.d/grafana.list ]]; then
    #       curl --silent https://packagecloud.io/gpg.key | apt-key add -
    #       echo "deb https://packagecloud.io/grafana/stable/debian/ wheezy main" > /etc/apt/sources.list.d/grafana.list
    #     fi
    #   ENDSCRIPT
    # end

    after "rubber:bootstrap", "rubber:grafana:bootstrap"

    task :bootstrap, :roles => :grafana do
      exists = capture("echo $(ls #{rubber_env.grafana_data_dir} 2> /dev/null)")
      if exists.strip.size == 0
        rubber.update_code_for_bootstrap
        rubber.run_config(:file => "role/grafana/", :force => true, :deploy_path => release_path)
        restart
        rubber.sudo "update-rc.d grafana-server defaults 95 10"
      end
    end

    task :start, :roles => :grafana do
      rsudo "service grafana-server start"
    end

    task :stop, :roles => :grafana do
      rsudo "service grafana-server stop || true"
    end

    task :restart, :roles => :grafana do
      stop
      start
    end

  end
end
