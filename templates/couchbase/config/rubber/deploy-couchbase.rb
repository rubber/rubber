namespace :rubber do

  namespace :couchbase do

    rubber.allow_optional_tasks(self)

    before "rubber:install_packages", "rubber:couchbase:setup_apt_sources"
  
    # sources needed for couchbase ruby client, not server
    task :setup_apt_sources do
      sources = <<-SOURCES
        # Ubuntu 11.10 Oneiric Ocelot (Debian unstable)
        #
        # preview version needed for ruby client that has rails cache/session
        #
        # deb http://packages.couchbase.com/ubuntu oneiric oneiric/main
        deb http://packages.couchbase.com/preview/ubuntu oneiric oneiric/main
      SOURCES
      sources.gsub!(/^[ \t]*/, '')
      put(sources, "/etc/apt/sources.list.d/couchbase.list") 
      rsudo "wget -O- http://packages.couchbase.com/ubuntu/couchbase.key | sudo apt-key add -"
    end

    after "rubber:install_packages", "rubber:couchbase:install"

    task :install, :roles => :couchbase do
      rubber.sudo_script 'install_couchbase', <<-ENDSCRIPT
        if ! grep "^#{rubber_env.couchbase_version}" /opt/couchbase/VERSION.txt &> /dev/null; then
          # Fetch and install the pkg
          rm -rf /tmp/couchbase*
          wget -qNP /tmp #{rubber_env.couchbase_pkg_url}
          dpkg -i /tmp/couchbase*

          # Clean up after ourselves.
          rm -rf /tmp/couchbase*
        fi
      ENDSCRIPT
    end

    after "rubber:bootstrap", "rubber:couchbase:bootstrap"

    task :bootstrap, :roles => :couchbase do
      exists = capture("echo $(ls #{rubber_env.couchbase_db_dir} 2> /dev/null)")
      if exists.strip.size == 0
        
        cli = rubber_env.couchbase_cli
        create_bucket_lines = []
        ram_size = 0
        rubber_env.couchbase_buckets.each do |bucket_spec|
          create_bucket_lines << "#{cli} bucket-create $cluster --bucket=#{bucket_spec['name']} --bucket-type=#{bucket_spec['type']} --bucket-port=#{bucket_spec['port']} --bucket-ramsize=#{bucket_spec['size']} --bucket-replica=#{bucket_spec['replicas']}"
          ram_size += bucket_spec['size'].to_i
        end
        
        rubber.sudo_script 'bootstrap_couchbase', <<-ENDSCRIPT
          mkdir -p #{rubber_env.couchbase_db_dir}
          chown -R couchbase:couchbase #{rubber_env.couchbase_db_dir}
          local_ip=$(ifconfig eth0 | awk -F"[: ]+" 'NR==2 {print $4}')
          cluster="-c $local_ip:8091 -u #{rubber_env.couchbase_admin_username} -p #{rubber_env.couchbase_admin_password}"

          # Setup cluster
          #{cli} cluster-init $cluster --cluster-init-ramsize=#{ram_size}

          # initialize the node
          #{cli} node-init $cluster --node-init-data-path=#{rubber_env.couchbase_db_dir}

          # create the buckets
          #{create_bucket_lines.join("\n")}

        ENDSCRIPT
  
        # After everything installed on machines, we need the source tree
        # on hosts in order to run rubber:config for bootstrapping the db
        rubber.update_code_for_bootstrap
  
        # Gen just the conf for couchbase
        rubber.run_config(:file => "role/couchbase/", :force => true, :deploy_path => release_path)
      
        restart
      end
    end

    desc "Stops the couchbase server"
    task :stop, :roles => :couchbase, :on_error => :continue do
      rsudo "service couchbase-server stop || true"
    end

    desc "Starts the couchbase server"
    task :start, :roles => :couchbase do
      rsudo "service couchbase-server status || service couchbase-server start"
    end

    desc "Restarts the couchbase server"
    task :restart, :roles => :couchbase do
      stop
      start
    end

    desc "Reloads the couchbase server"
    task :reload, :roles => :couchbase do
      restart
    end

  end

end
