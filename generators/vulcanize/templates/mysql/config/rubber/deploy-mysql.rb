
namespace :rubber do
  
  namespace :mysql do
    
    rubber.allow_optional_tasks(self)
    
    after "rubber:create", "rubber:mysql:validate_db_roles"

    task :validate_db_roles do
      db_instances = rubber_instances.for_role("mysql_slave")
      db_instances.each do |instance|
        if instance.role_names.find {|n| n == 'mysql_master'}
          fatal "Cannot have a mysql slave and master on the same instance, please removing slave role for #{instance.name}"
        end
      end
    end

    after "rubber:bootstrap", "rubber:mysql:bootstrap"
  
    
    # Bootstrap the production database config.  Db bootstrap is special - the
    # user could be requiring the rails env inside some of their config
    # templates, which creates a catch 22 situation with the db, so we try and
    # bootstrap the db separate from the rest of the config
    task :bootstrap, :roles => [:mysql_master, :mysql_slave] do
      
      # Conditionaly bootstrap for each node/role only if that node has not
      # been boostrapped for that role before
      
      master_instances = rubber_instances.for_role("mysql_master") & rubber_instances.filtered  
      master_instances.each do |ic|
        task_name = "_bootstrap_mysql_master_#{ic.full_name}".to_sym()
        task task_name, :hosts => ic.full_name do
          env = rubber_cfg.environment.bind("mysql_master", ic.name)
          exists = capture("echo $(ls #{env.db_data_dir}/ 2> /dev/null)")
          if exists.strip.size == 0
            common_bootstrap("mysql_master")
            
            pass = "identified by '#{env.db_pass}'" if env.db_pass
            sudo "mysql -u root -e 'create database #{env.db_name};'"
            sudo "mysql -u root -e \"grant all on *.* to '#{env.db_user}'@'%' #{pass};\""
            sudo "mysql -u root -e \"grant select on *.* to '#{env.db_slave_user}'@'%' #{pass};\""
            sudo "mysql -u root -e \"grant replication slave on *.* to '#{env.db_replicator_user}'@'%' #{pass};\""
            sudo "mysql -u root -e \"flush privileges;\""
          end
        end
        send task_name
      end
    
      slave_instances = rubber_instances.for_role("mysql_slave") & rubber_instances.filtered  
      slave_instances.each do |ic|
        task_name = "_bootstrap_mysql_slave_#{ic.full_name}".to_sym()
        task task_name, :hosts => ic.full_name do
          env = rubber_cfg.environment.bind("mysql_slave", ic.name)
          exists = capture("echo $(ls #{env.db_data_dir}/ 2> /dev/null)")
          if exists.strip.size == 0
            common_bootstrap("mysql_slave")

            master = rubber_instances.for_role("mysql_master").first

            # Doing a mysqldump locks the db, so ideally we'd do it against a slave replica thats
            # not serving traffic (mysql_util role), but if thats not available try a regular
            # slave (mysql_slave role), and finally default dumping from master (mysql_master role)
            # TODO: handle simultaneous creating of multi slaves/utils
            slaves = rubber_instances.for_role("mysql_slave")
            slaves.delete(ic) # don't want to try and dump from self
            source = slaves.find {|sc| sc.role_names.include?("mysql_util")}
            source = slaves.first unless source
            source = master unless source

            pass = "identified by '#{env.db_pass}'" if env.db_pass
            master_pass = ", master_password='#{env.db_pass}'" if env.db_pass
            master_host = master.full_name
            source_host = source.full_name

            if source == master
              logger.info "Creating slave from a dump of master #{source_host}"
              sudo "mysql -u root -e \"change master to master_host='#{master_host}', master_user='#{env.db_replicator_user}' #{master_pass}\""
              sudo "sh -c 'mysqldump -u #{env.db_user} #{pass} -h #{source_host} --all-databases --master-data=1 | mysql -u root'"
            else
              logger.info "Creating slave from a dump of slave #{source_host}"
              sudo "mysql -u #{env.db_user} #{pass} -h #{source_host} -e \"stop slave;\""
              slave_status = capture("mysql -u #{env.db_user} #{pass} -h #{source_host} -e \"show slave status\\G\"")
              slave_config = Hash[*slave_status.scan(/([^\s:]+): ([^\s]*)/).flatten]
              log_file = slave_config['Master_Log_File']
              log_pos = slave_config['Read_Master_Log_Pos']
              sudo "sh -c 'mysqldump -u #{env.db_user} #{pass} -h #{source_host} --all-databases --master-data=1 | mysql -u root'"
              sudo "mysql -u root -e \"change master to master_host='#{master_host}', master_user='#{env.db_replicator_user}', master_log_file='#{log_file}', master_log_pos=#{log_pos} #{master_pass}\""
              sudo "mysql -u #{env.db_user} #{pass} -h #{source_host} -e \"start slave;\""
            end

            # this doesn't work without agent forwarding which sudo breaks, as well as not having your
            # ec2 private key ssh-added on workstation
            # sudo "scp -o \"StrictHostKeyChecking=no\" #{source_host}:/etc/mysql/debian.cnf /etc/mysql"

            sudo "mysql -u root -e \"flush privileges;\""
            sudo "mysql -u root -e \"start slave;\""
          end
        end
        send task_name
      end
      
    end
  
    # TODO: Make the setup/update happen just once per host
    def common_bootstrap(role)
      # mysql package install starts mysql, so stop it
      sudo "/etc/init.d/mysql stop" rescue nil
      
      # After everything installed on machines, we need the source tree
      # on hosts in order to run rubber:config for bootstrapping the db
      deploy.setup
      deploy.update_code
      
      # Gen just the conf for the given mysql role
      rubber.run_config(:RUBBER_ENV => RUBBER_ENV, :FILE => "role/#{role}|role/db/", :FORCE => true, :deploy_path => release_path)

      # reconfigure mysql so that it sets up data dir in /mnt with correct files
      sudo_script 'reconfigure-mysql', <<-ENDSCRIPT
        server_package=`dpkg -l | grep mysql-server-[0-9] | awk '{print $2}'`
        dpkg-reconfigure --frontend=noninteractive $server_package
      ENDSCRIPT
      sleep 5
    end
    
    before "rubber:munin:custom_install", "rubber:mysql:custom_install_munin"

    desc <<-DESC
      Installs some extra munin graphs
    DESC
    task :custom_install_munin, :roles => [:mysql_master, :mysql_slave] do
      rubber.sudo_script 'install_munin_mysql', <<-ENDSCRIPT
        if [ ! -f /usr/share/munin/plugins/mysql_ ]; then
          wget -q -O /usr/share/munin/plugins/mysql_ http://github.com/kjellm/munin-mysql/raw/master/mysql_
          wget -q -O /etc/munin/plugin-conf.d/mysql_.conf http://github.com/kjellm/munin-mysql/raw/master/mysql_.conf
        fi
      ENDSCRIPT
    end

    desc <<-DESC
      Starts the mysql daemons
    DESC
    task :start, :roles => [:mysql_master, :mysql_slave] do
      sudo "/etc/init.d/mysql start"
    end
    
    desc <<-DESC
      Stops the mysql daemons
    DESC
    task :stop, :roles => [:mysql_master, :mysql_slave] do
      sudo "/etc/init.d/mysql stop"
    end
  
    desc <<-DESC
      Restarts the mysql daemons
    DESC
    task :restart, :roles => [:mysql_master, :mysql_slave] do
      sudo "/etc/init.d/mysql restart"
    end

    desc <<-DESC
      Backup production database using rake task rubber:backup_db
    DESC
    task :backup, :roles => [:mysql_master, :mysql_slave] do
      master_instances = rubber_instances.for_role("mysql_master")
      slaves = rubber_instances.for_role("mysql_slave")

      # Select only one instance for backup.  Favor slave database.
      selected_mysql_instance = (slaves+master_instances).first
            
      task_name = "_backup_mysql_slave_#{selected_mysql_instance.full_name}".to_sym()
      task task_name, :hosts => selected_mysql_instance.full_name do
        run "cd #{current_path} && RUBBER_ENV=production RAILS_ENV=production RUBYOPT=rubygems BACKUP_DIR=/mnt/db_backups DBUSER=#{rubber_env.db_user} DBPASS=#{rubber_env.db_pass} DBNAME=#{rubber_env.db_name} DBHOST=#{selected_mysql_instance.full_name} rake rubber:backup_db"
      end
      send task_name
    end
    
    desc <<-DESC
      Restore production database from s3 using rake task rubber:restore_db_s3
    DESC
    task :restore_s3, :roles => [:mysql_master, :mysql_slave] do
      master_instances = rubber_instances.for_role("mysql_master")
      slaves = rubber_instances.for_role("mysql_slave")

      for instance in master_instances+slaves
        task_name = "_restore_mysql_s3_#{instance.full_name}".to_sym()
        task task_name, :hosts => instance.full_name do
          run "cd #{current_path} && RUBBER_ENV=production RAILS_ENV=production RUBYOPT=rubygems BACKUP_DIR=/mnt/db_backups DBUSER=#{rubber_env.db_user} DBPASS=#{rubber_env.db_pass} DBNAME=#{rubber_env.db_name} DBHOST=#{instance.full_name} rake rubber:restore_db_s3"
        end
        send task_name
      end
    end    
    
    desc <<-DESC
      Overwrite ec2 production database with export from local production database.
    DESC
    task :local_to_ec2, :roles => [:mysql_master, :mysql_slave] do
      require 'yaml'      
      master_instances = rubber_instances.for_role("mysql_master")
      slaves = rubber_instances.for_role("mysql_slave")

      # Select only one instance for backup.  Favor slave database.
      selected_mysql_instance = (slaves+master_instances).first
            
      task_name = "_load_local_to_#{selected_mysql_instance.full_name}".to_sym()
      task task_name, :hosts => selected_mysql_instance.full_name do

        # Dump Local to tmp folder
        filename = "#{application}.local.#{Time.now.to_i}.sql.gz" 
        backup_file = "/tmp/#{filename}" 
        on_rollback { delete file }
        FileUtils.mkdir_p(File.dirname(backup_file))

        # Use database.yml to get connection params
        db = YAML::load(ERB.new(IO.read(File.join(File.dirname(__FILE__), '..','database.yml'))).result)['production']
        user = db['username']
        pass = db['passsword']
        pass = nil if pass and pass.strip.size == 0
        host = db['host']
        name = db['database']
        
        raise "No db_backup_cmd defined in rubber.yml, cannot backup!" unless rubber_env.db_backup_cmd
        db_backup_cmd = rubber_env.db_backup_cmd.gsub(/%([^%]+)%/, '#{\1}')
        db_backup_cmd = eval('%Q{' + db_backup_cmd + '}')

        # mysqldump (or backup app) needs to be in your path
        puts "Backing up database with command:"
        system(db_backup_cmd)
        puts "Created backup: #{backup_file}"

        # Upload Local to S3
        cloud_provider = rubber_env.cloud_providers[rubber_env.cloud_provider]
        s3_prefix = "db/"
        backup_bucket = cloud_provider.backup_bucket
        if backup_bucket
          AWS::S3::Base.establish_connection!(:access_key_id => cloud_provider.access_key, :secret_access_key => cloud_provider.secret_access_key)
          unless AWS::S3::Bucket.list.find { |b| b.name == backup_bucket }
            AWS::S3::Bucket.create(backup_bucket)
          end
          dest = "#{s3_prefix}#{File.basename(backup_file)}"
          puts "Saving db dump to S3: #{backup_bucket}:#{dest}"
          AWS::S3::S3Object.store(dest, open(backup_file), backup_bucket)
        end
        
        send :restore_s3

      end
      send task_name
    end    
  
  end

end
