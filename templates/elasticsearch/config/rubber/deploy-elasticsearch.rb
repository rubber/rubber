namespace :rubber do

  namespace :elasticsearch do

    rubber.allow_optional_tasks(self)

    after "rubber:install_packages", "rubber:elasticsearch:install"

    task :install, :roles => :elasticsearch do
      rubber.sudo_script 'install_elasticsearch', <<-ENDSCRIPT
        if [[ ! -f /usr/share/elasticsearch/lib/elasticsearch-#{rubber_env.elasticsearch_version}.jar ]]; then
          wget -qNP /tmp https://download.elasticsearch.org/elasticsearch/elasticsearch/elasticsearch-#{rubber_env.elasticsearch_version}.deb
          dpkg -i /tmp/elasticsearch-#{rubber_env.elasticsearch_version}.deb
          rm /tmp/elasticsearch-#{rubber_env.elasticsearch_version}.deb

          rm -rf /usr/share/elasticsearch/plugins/head
          /usr/share/elasticsearch/bin/plugin install mobz/elasticsearch-head
        fi
      ENDSCRIPT
    end

    after "rubber:bootstrap", "rubber:elasticsearch:bootstrap"

    task :bootstrap, :roles => :elasticsearch do
      exists = capture("echo $(ls #{rubber_env.elasticsearch_data_dir} 2> /dev/null)")
      if exists.strip.size == 0
        rubber.sudo_script 'bootstrap_redis', <<-ENDSCRIPT
          for d in #{rubber_env.elasticsearch_data_dir} #{rubber_env.elasticsearch_work_dir} #{rubber_env.elasticsearch_log_dir}; do
            if [ ! -d $d ]; then
              mkdir -p $d
              chown -R elasticsearch:elasticsearch $d
            fi
          done
        ENDSCRIPT

        # After everything installed on machines, we need the source tree
        # on hosts in order to run rubber:config for bootstrapping the db
        rubber.update_code_for_bootstrap
        rubber.run_config(:file => "role/elasticsearch/", :force => true, :deploy_path => release_path)

        restart
      end
    end

    task :start, :roles => :elasticsearch do
      rsudo "#{service_status('elasticsearch')} || #{service_start('elasticsearch')}"
    end

    task :stop, :roles => :elasticsearch do
      rsudo "#{service_stop('elasticsearch')} || true"
    end

    task :restart, :roles => :elasticsearch do
      stop
      start
    end

  end
end
