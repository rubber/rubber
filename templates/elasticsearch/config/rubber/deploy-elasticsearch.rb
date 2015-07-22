namespace :rubber do

  namespace :elasticsearch do

    rubber.allow_optional_tasks(self)

    before "rubber:install_packages", "rubber:elasticsearch:setup_apt_sources"

    task :setup_apt_sources, :roles => :elasticsearch do
      rubber.sudo_script 'setup_elasticsearch_apt', <<-ENDSCRIPT
        if [[ ! -f /etc/apt/sources.list.d/elasticsearch.list ]]; then
          curl --silent https://packages.elastic.co/GPG-KEY-elasticsearch | apt-key add -
          echo "deb http://packages.elastic.co/elasticsearch/#{rubber_env.elasticsearch_major_version}/debian stable main" > /etc/apt/sources.list.d/elasticsearch.list
        fi
      ENDSCRIPT
    end

    after "rubber:install_packages", "rubber:elasticsearch:install"

    task :install, :roles => :elasticsearch do
      rubber.sudo_script 'install_elasticsearch', <<-ENDSCRIPT
        if [[ ! -d "#{rubber_env.elasticsearch_dir}/plugins/head" ]]; then
          #{rubber_env.elasticsearch_dir}/bin/plugin --install mobz/elasticsearch-head;
        fi
      ENDSCRIPT

      pip install elasticsearch-curator
    end

    after "rubber:bootstrap", "rubber:elasticsearch:bootstrap"

    task :bootstrap, :roles => :elasticsearch do
      exists = capture("echo $(ls #{rubber_env.elasticsearch_data_dir} 2> /dev/null)")
      if exists.strip.size == 0
        rubber.update_code_for_bootstrap
        rubber.run_config(:file => "role/elasticsearch/", :force => true, :deploy_path => release_path)

        restart
      end
    end

    task :start, :roles => :elasticsearch do
      rsudo "service elasticsearch start"
    end

    task :stop, :roles => :elasticsearch do
      rsudo "service elasticsearch stop || true"
    end

    task :restart, :roles => :elasticsearch do
      stop
      start
    end

  end
end
