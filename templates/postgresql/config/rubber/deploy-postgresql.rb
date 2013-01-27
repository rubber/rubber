namespace :rubber do
  
  namespace :postgresql do
    
    rubber.allow_optional_tasks(self)

    before "rubber:install_packages", "rubber:postgresql:setup_apt_sources"

    task :setup_apt_sources do
      rubber.sudo_script 'configure_postgresql_repository', <<-ENDSCRIPT
        # PostgreSQL 9.1 is the default starting in Ubuntu 11.10.
        release=`lsb_release -sr`
        needs_repo=`echo "$release < 11.10" | bc`
        if [[ $needs_repo == 1 ]]; then
          add-apt-repository ppa:pitti/postgresql
        fi
      ENDSCRIPT
    end
    
    after "rubber:create", "rubber:postgresql:validate_db_roles"

    task :validate_db_roles do
      db_instances = rubber_instances.for_role("postgresql_slave")
      db_instances.each do |instance|
        if instance.role_names.find {|n| n == 'postgresql_master'}
          fatal "Cannot have a postgresql slave and master on the same instance, please remove slave role for #{instance.name}"
        end
      end
    end

    after "rubber:bootstrap", "rubber:postgresql:bootstrap"
    
    # Bootstrap the production database config.  Db bootstrap is special - the
    # user could be requiring the rails env inside some of their config
    # templates, which creates a catch 22 situation with the db, so we try and
    # bootstrap the db separate from the rest of the config
    task :bootstrap, :roles => [:postgresql_master, :postgresql_slave] do
      
      # Conditionally bootstrap for each node/role only if that node has not
      # been bootstrapped for that role before
      master_instances = rubber_instances.for_role("postgresql_master") & rubber_instances.filtered  
      master_instances.each do |ic|
        task_name = "_bootstrap_postgresql_master_#{ic.full_name}".to_sym()
        task task_name, :hosts => ic.full_name do
          env = rubber_cfg.environment.bind("postgresql_master", ic.name)
          exists = capture("echo $(ls #{env.postgresql_data_dir}/ 2> /dev/null)")
          if exists.strip.size == 0
            common_bootstrap
            sudo "/usr/lib/postgresql/#{rubber_env.postgresql_ver}/bin/initdb -D #{rubber_env.postgresql_data_dir}", :as => 'postgres'
            sudo "#{rubber_env.postgresql_ctl} start"
            sleep 5

            create_user_cmd = "CREATE USER #{env.db_user} WITH NOSUPERUSER CREATEDB NOCREATEROLE"
            create_user_cmd << " PASSWORD '#{env.db_pass}'" if env.db_pass

            create_replication_user_cmd = "CREATE USER #{env.db_replication_user} WITH NOSUPERUSER NOCREATEROLE REPLICATION"
            create_replication_user_cmd << " PASSWORD '#{env.db_replication_pass}'" if env.db_replication_pass

            rubber.sudo_script "create_master_db", <<-ENDSCRIPT
              sudo -i -u postgres psql -c "#{create_user_cmd}"
              sudo -i -u postgres psql -c "#{create_replication_user_cmd}"
              sudo -i -u postgres psql -c "CREATE DATABASE #{env.db_name} WITH OWNER #{env.db_user}"
            ENDSCRIPT
          end
        end
        send task_name
      end

      slave_instances = rubber_instances.for_role("postgresql_slave") & rubber_instances.filtered
      slave_instances.each do |ic|
        task_name = "_bootstrap_postgresql_slave_#{ic.full_name}".to_sym()
        task task_name, :hosts => ic.full_name do
          env = rubber_cfg.environment.bind("postgresql_slave", ic.name)
          exists = capture("echo $(ls #{env.postgresql_data_dir}/ 2> /dev/null)")
          if exists.strip.size == 0
            common_bootstrap
            master = rubber_instances.for_role("postgresql_master").first

            rsudo "/usr/lib/postgresql/#{env.postgresql_ver}/bin/pg_basebackup -D #{env.postgresql_data_dir} -U #{env.db_replication_user} -h #{master.full_name}", :as => 'postgres'

            # Gen just the slave-specific conf.
            rubber.run_config(:file => "role/postgresql_slave/", :force => true, :deploy_path => release_path)

            # Start up the server.
            rsudo "#{rubber_env.postgresql_ctl} start"
            sleep 5
          end
        end

        send task_name
      end
    end

    # TODO: Make the setup/update happen just once per host
    def common_bootstrap
      # postgresql package install starts postgresql, so stop it
      rsudo "#{rubber_env.postgresql_ctl} stop" rescue nil
      
      # After everything installed on machines, we need the source tree
      # on hosts in order to run rubber:config for bootstrapping the db
      rubber.update_code_for_bootstrap

      # Gen just the conf for the given postgresql role
      rubber.run_config(:file => "role/(db|postgresql)/", :force => true, :deploy_path => release_path)

      # reconfigure postgresql so that it sets up data dir in /mnt with correct files
      dirs = [rubber_env.postgresql_data_dir, rubber_env.postgresql_archive_dir]
      sudo_script 'reconfigure-postgresql', <<-ENDSCRIPT
        mkdir -p #{dirs.join(' ')}
        chown -R postgres:postgres #{dirs.join(' ')}
        chmod 700 #{rubber_env.postgresql_data_dir}
      ENDSCRIPT
    end

    desc <<-DESC
      Promotes a slave instance to master
    DESC
    task :promote_slave do
      master_alias = get_env('MASTER', "Master alias (e.g. db01)", true)
      slave_alias = get_env('SLAVE', "Slave alias (e.g. db02)", true)
      
      # remove the master instance so rubber doesn't try to deploy to it
      # Stays running so needs to be manually deleted
      master_instance = rubber_instances.remove(master_alias)
      fatal "Master Instance does not exist: #{master_alias}" unless master_instance
      
      slave_instance = rubber_instances[slave_alias]
      fatal "Slave Instance does not exist: #{slave_alias}" unless slave_instance
      
      # remove all db roles from slave
      slave_instance.roles.delete_if {|ir| ir.name =~ /db|postgresql/ }

      # add in master db roles to slave
      new_roles = [Rubber::Configuration::RoleItem.parse("postgresql_master")]
      new_roles = Rubber::Configuration::RoleItem.expand_role_dependencies(new_roles, get_role_dependencies)
      slave_instance.roles = (slave_instance.roles + new_roles).uniq
      
      rubber_instances.save()
      
      begin
        Timeout::timeout(10) do
          logger.info "Stopping server on original master #{master_alias}"
          rsudo "service monit stop || true", :hosts => master_instance.full_name
          rsudo "service postgresql stop || true", :hosts => master_instance.full_name
        end
      rescue StandardError
        logger.info "Failed to connect to original master, promoting slave anyway"
      end
      
      logger.info "Triggering slave promotion on new master #{slave_alias}"
      rsudo "touch #{rubber_env.postgresql_data_dir}/trigger_file", :hosts => slave_instance.full_name
      
      logger.info "The master instance has been removed from instances, but remains running:"
      logger.info "#{master_alias}, #{master_instance.instance_id}, #{master_instance.external_ip}"
      logger.info ''
      logger.info "Roles for #{slave_alias} are now:"
      logger.info slave_instance.roles.inspect
      logger.info ''
      logger.info "Promotion complete, you should commit the instance file and deploy"
    end

    desc <<-DESC
      Starts the postgresql daemons
    DESC
    task :start, :roles => [:postgresql_master, :postgresql_slave] do
      rsudo "#{rubber_env.postgresql_ctl} start"
    end
    
    desc <<-DESC
      Stops the postgresql daemons
    DESC
    task :stop, :roles => [:postgresql_master, :postgresql_slave] do
      rsudo "#{rubber_env.postgresql_ctl} stop || true"
    end
  
    desc <<-DESC
      Restarts the postgresql daemons
    DESC
    task :restart, :roles => [:postgresql_master, :postgresql_slave] do
      stop
      start
    end

  end

end