
namespace :rubber do
  
  namespace :postgresql do
    
    rubber.allow_optional_tasks(self)

    before "rubber:install_packages", "rubber:postgresql:setup_apt_sources"

    task :setup_apt_sources do
      rsudo "add-apt-repository ppa:pitti/postgresql"
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
      # been boostrapped for that role before
      master_instances = rubber_instances.for_role("postgresql_master") & rubber_instances.filtered  
      master_instances.each do |ic|
        task_name = "_bootstrap_postgresql_master_#{ic.full_name}".to_sym()
        task task_name, :hosts => ic.full_name do
          env = rubber_cfg.environment.bind("postgresql_master", ic.name)
          exists = capture("echo $(ls #{env.postgresql_data_dir}/ 2> /dev/null)")
          if exists.strip.size == 0
            common_bootstrap("postgresql_master")
            sudo "/usr/lib/postgresql/#{rubber_env.postgresql_ver}/bin/initdb -D #{rubber_env.postgresql_data_dir}", :as => 'postgres'
            sudo "#{rubber_env.postgresql_ctl} start"
            sleep 5

            create_user_cmd = "CREATE USER #{env.db_user} WITH NOSUPERUSER CREATEDB NOCREATEROLE"
            create_user_cmd << "PASSWORD '#{env.db_pass}'" if env.db_pass
            rubber.sudo_script "create_master_db", <<-ENDSCRIPT
              sudo -u postgres psql -c "#{create_user_cmd}"
              sudo -u postgres psql -c "CREATE DATABASE #{env.db_name} WITH OWNER #{env.db_user}"
              sudo -u postgres createlang plpythonu #{env.db_name}
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
            common_bootstrap("postgresql_slave")

            source = master = rubber_instances.for_role("postgresql_master").first

            slave_pub_key = capture("cat /root/.ssh/id_dsa.pub")
            sudo "echo \"#{slave_pub_key}\" >> /root/.ssh/authorized_keys", :hosts => [master.full_name]

            base_backup_script = <<-ENDSCRIPT
              sudo -u postgres psql -c "SELECT pg_start_backup('rubber_create_slave')";
              rsync -a #{env.postgresql_data_dir}/* #{ic.full_name}:#{env.postgresql_data_dir}/ --exclude postmaster.pid --exclude recovery.* --exclude trigger_file;
              sudo -u postgres psql -c "SELECT pg_stop_backup()"
            ENDSCRIPT

            sudo base_backup_script, :hosts => [master.full_name]

            # Gen just the slave-specific conf.
            rubber.run_config(:RUBBER_ENV => RUBBER_ENV, :FILE => "role/postgresql_slave/", :FORCE => true, :deploy_path => release_path)

            # Start up the server.
            sudo "#{rubber_env.postgresql_ctl} start"
            sleep 5
          end
        end

        send task_name
      end
    end

    after "rubber:munin:custom_install", "rubber:postgresql:install_munin_plugins"
    after "rubber:postgresql:install_munin_plugins", "rubber:munin:restart"
    task :install_munin_plugins, :roles => [:postgresql_master, :postgresql_slave] do
      regular_plugins = %w[bgwriter checkpoints connections_db users xlog]
      parameterized_plugins = %w[cache connections locks querylength scans transactions tuples]

      commands = ['rm -f /etc/munin/plugins/postgres_*']

      regular_plugins.each do |name|
        commands << "ln -s /usr/share/munin/plugins/postgres_#{name} /etc/munin/plugins/postgres_#{name}"
      end

      parameterized_plugins.each do |name|
        commands << "ln -s /usr/share/munin/plugins/postgres_#{name}_ /etc/munin/plugins/postgres_#{name}_#{rubber_env.db_name}"
      end

      rubber.sudo_script "install_postgresql_munin_plugins", <<-ENDSCRIPT
        #{commands.join(';')}
      ENDSCRIPT
    end
  
    # TODO: Make the setup/update happen just once per host
    def common_bootstrap(role)
      # postgresql package install starts postgresql, so stop it
      rsudo "#{rubber_env.postgresql_ctl} stop" rescue nil
      
      # After everything installed on machines, we need the source tree
      # on hosts in order to run rubber:config for bootstrapping the db
      rubber.update_code_for_bootstrap

      # Gen just the conf for the given postgresql role
      rubber.run_config(:RUBBER_ENV => RUBBER_ENV, :FILE => "role/#{role}|role/db/", :FORCE => true, :deploy_path => release_path)

      # reconfigure postgresql so that it sets up data dir in /mnt with correct files
      dirs = [rubber_env.postgresql_data_dir, rubber_env.postgresql_archive_dir]
      sudo_script 'reconfigure-postgresql', <<-ENDSCRIPT
        mkdir -p #{dirs.join(' ')}
        chown -R postgres:postgres #{dirs.join(' ')}
        chmod 700 #{rubber_env.postgresql_data_dir}
      ENDSCRIPT
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
      rsudo "#{rubber_env.postgresql_ctl} stop"
    end
  
    desc <<-DESC
      Restarts the postgresql daemons
    DESC
    task :restart, :roles => [:postgresql_master, :postgresql_slave] do
      rsudo "#{rubber_env.postgresql_ctl} restart"
    end

  end

end
