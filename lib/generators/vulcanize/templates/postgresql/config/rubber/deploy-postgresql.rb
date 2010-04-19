
namespace :rubber do
  
  namespace :postgresql do
    
    rubber.allow_optional_tasks(self)
    
    after "rubber:create", "rubber:postgresql:validate_db_roles"

    task :validate_db_roles do
      db_instances = rubber_instances.for_role("postgresql_slave")
      db_instances.each do |instance|
        if instance.role_names.find {|n| n == 'postgresql_master'}
          fatal "Cannot have a postgresql slave and master on the same instance, please removing slave role for #{instance.name}"
        end
      end
    end

    after "rubber:bootstrap", "rubber:postgresql:bootstrap"
  
    
    # Bootstrap the production database config.  Db bootstrap is special - the
    # user could be requiring the rails env inside some of their config
    # templates, which creates a catch 22 situation with the db, so we try and
    # bootstrap the db separate from the rest of the config
    task :bootstrap, :roles => [:postgresql_master, :postgresql_slave] do
      
      # Conditionaly bootstrap for each node/role only if that node has not
      # been boostrapped for that role before
      
      master_instances = rubber_instances.for_role("postgresql_master") & rubber_instances.filtered  
      master_instances.each do |ic|
        task_name = "_bootstrap_postgresql_master_#{ic.full_name}".to_sym()
        task task_name, :hosts => ic.full_name do
          env = rubber_cfg.environment.bind("postgresql_master", ic.name)
          exists = capture("echo $(ls #{env.postgres_data_dir}/ 2> /dev/null)")
          if exists.strip.size == 0
            common_bootstrap("postgresql_master")
            
            pass = "identified by '#{env.db_pass}'" if env.db_pass
            rubber.sudo_script "create_master_db", <<-ENDSCRIPT
              psql -u root -e "create database #{env.db_name};"
              psql -u root -e "grant all on *.* to '#{env.db_user}'@'%' #{pass};"
              psql -u root -e "grant select on *.* to '#{env.db_slave_user}'@'%' #{pass};"
              psql -u root -e "grant replication slave on *.* to '#{env.db_replicator_user}'@'%' #{pass};"
              psql -u root -e "flush privileges;"
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
          exists = capture("echo $(ls #{env.db_data_dir}/ 2> /dev/null)")
          if exists.strip.size == 0
            common_bootstrap("postgresql_slave")

            master = rubber_instances.for_role("postgresql_master").first

            # Doing a postgresqldump locks the db, so ideally we'd do it against a slave replica thats
            # not serving traffic (postgresql_util role), but if thats not available try a regular
            # slave (postgresql_slave role), and finally default dumping from master (postgresql_master role)
            # TODO: handle simultaneous creating of multi slaves/utils
            slaves = rubber_instances.for_role("postgresql_slave")
            slaves.delete(ic) # don't want to try and dump from self
            source = slaves.find {|sc| sc.role_names.include?("postgresql_util")}
            source = slaves.first unless source
            source = master unless source

            pass = "identified by '#{env.db_pass}'" if env.db_pass
            master_pass = ", master_password='#{env.db_pass}'" if env.db_pass
            master_host = master.full_name
            source_host = source.full_name

            if source == master
              logger.info "Creating slave from a dump of master #{source_host}"
              rubber.sudo_script "create_slave_db_from_master", <<-ENDSCRIPT
                psql -u root -e "change master to master_host='#{master_host}', master_user='#{env.db_replicator_user}' #{master_pass}"
                psqldump -u #{env.db_user} --password #{env.db_pass} -h #{source_host} --all-databases --master-data=1 | psql -u root
              ENDSCRIPT
            else
              logger.info "Creating slave from a dump of slave #{source_host}"
              rsudo "psql -u #{env.db_user} --password #{env.db_pass} -h #{source_host} -e \"stop slave;\""
              slave_status = capture("psql -u #{env.db_user} #{pass} -h #{source_host} -e \"show slave status\\G\"")
              slave_config = Hash[*slave_status.scan(/([^\s:]+): ([^\s]*)/).flatten]
              log_file = slave_config['Master_Log_File']
              log_pos = slave_config['Read_Master_Log_Pos']
              rubber.sudo_script "create_slave_db_from_slave", <<-ENDSCRIPT
                psqldump -u #{env.db_user} --password #{env.db_pass} -h #{source_host} --all-databases --master-data=1 | psql -u root
                psql -u root -e "change master to master_host='#{master_host}', master_user='#{env.db_replicator_user}', master_log_file='#{log_file}', master_log_pos=#{log_pos} #{master_pass}"
                psql -u #{env.db_user} --password #{env.db_pass} -h #{source_host} -e "start slave;"
              ENDSCRIPT
            end

            # this doesn't work without agent forwarding which sudo breaks, as well as not having your
            # ec2 private key ssh-added on workstation
            # sudo "scp -o \"StrictHostKeyChecking=no\" #{source_host}:/etc/postgresql/debian.cnf /etc/postgresql"

            rsudo "psql -u root -e \"flush privileges;\""
            rsudo "psql -u root -e \"start slave;\""
          end
        end
        send task_name
      end
      
    end
  
    # TODO: Make the setup/update happen just once per host
    def common_bootstrap(role)
      # postgresql package install starts postgresql, so stop it
      rsudo "/etc/init.d/postgresql-8.4 stop" rescue nil
      
      # After everything installed on machines, we need the source tree
      # on hosts in order to run rubber:config for bootstrapping the db
      deploy.setup
      deploy.update_code
      
      # Gen just the conf for the given postgresql role
      rubber.run_config(:RUBBER_ENV => RUBBER_ENV, :FILE => "role/#{role}|role/db/", :FORCE => true, :deploy_path => release_path)

      # reconfigure postgresql so that it sets up data dir in /mnt with correct files
      sudo_script 'reconfigure-postgresql', <<-ENDSCRIPT
        server_package=`dpkg -l | grep postgresql-[0-9] | awk '{print $2}'`
        dpkg-reconfigure --frontend=noninteractive $server_package
      ENDSCRIPT
      sleep 5
    end
    
    desc <<-DESC
      Starts the postgresql daemons
    DESC
    task :start, :roles => [:postgresql_master, :postgresql_slave] do
      rsudo "#{rubber_env.postgres_ctl} start"
    end
    
    desc <<-DESC
      Stops the postgresql daemons
    DESC
    task :stop, :roles => [:postgresql_master, :postgresql_slave] do
      rsudo "#{rubber_env.postgres_ctl} stop"
    end
  
    desc <<-DESC
      Restarts the postgresql daemons
    DESC
    task :restart, :roles => [:postgresql_master, :postgresql_slave] do
      rsudo "#{rubber_env.postgres_ctl} restart"
    end

  end

end
