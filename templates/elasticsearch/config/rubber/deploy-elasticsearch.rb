namespace :rubber do

  namespace :elasticsearch do

    rubber.allow_optional_tasks(self)

    after "rubber:install_packages", "rubber:elasticsearch:install"

    task :install, :roles => :elasticsearch do
      rubber.sudo_script 'install_elasticsearch', <<-ENDSCRIPT
        if [[ ! -d "#{rubber_env.elasticsearch_dir}" ]]; then
          wget --no-check-certificate -qNP /tmp http://download.elasticsearch.org/elasticsearch/elasticsearch/elasticsearch-#{rubber_env.elasticsearch_version}.zip
          unzip -d #{rubber_env.elasticsearch_prefix} /tmp/elasticsearch-#{rubber_env.elasticsearch_version}.zip
          rm /tmp/elasticsearch-#{rubber_env.elasticsearch_version}.zip

          #{rubber_env.elasticsearch_dir}/bin/plugin -install mobz/elasticsearch-head
          
        fi
      ENDSCRIPT
    end

    after "rubber:bootstrap", "rubber:elasticsearch:bootstrap"

    task :bootstrap, :roles => :elasticsearch do
      exists = capture("echo $(ls /etc/init/elasticsearch.conf 2> /dev/null)")
      if exists.strip.size == 0
        # After everything installed on machines, we need the source tree
        # on hosts in order to run rubber:config for bootstrapping the db
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
