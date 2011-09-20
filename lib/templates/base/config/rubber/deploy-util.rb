namespace :rubber do
  namespace :util do
  
    rubber.allow_optional_tasks(self)
   
    desc <<-DESC
      Backup database using rake task rubber:backup_db
    DESC
    task :backup do
      master_instances = rubber_instances.for_role('db', 'primary' => true)
      slaves = rubber_instances.for_role('db', {})

      # Select only one instance for backup.  Favor slave database.
      selected_db_instance = (slaves+master_instances).first
            
      task_name = "_backup_db_#{selected_db_instance.full_name}".to_sym()
      task task_name, :hosts => selected_db_instance.full_name do
        rsudo "cd #{current_path} && RUBBER_ENV=#{RUBBER_ENV} BACKUP_DIR=/mnt/db_backups DBUSER=#{rubber_env.db_user} DBPASS=#{rubber_env.db_pass} DBNAME=#{rubber_env.db_name} DBHOST=#{selected_db_instance.full_name} rake rubber:backup_db"
      end
      send task_name
    end
    
    desc <<-DESC
      Restore database from s3 using rake task rubber:restore_db_s3
    DESC
    task :restore_s3 do
      master_instances = rubber_instances.for_role('db', 'primary' => true)
      slaves = rubber_instances.for_role('db', {})

      for instance in master_instances+slaves
        task_name = "_restore_db_s3_#{instance.full_name}".to_sym()
        task task_name, :hosts => instance.full_name do
          rsudo "cd #{current_path} && RUBBER_ENV=#{RUBBER_ENV} BACKUP_DIR=/mnt/db_backups DBUSER=#{rubber_env.db_user} DBPASS=#{rubber_env.db_pass} DBNAME=#{rubber_env.db_name} DBHOST=#{instance.full_name} rake rubber:restore_db_s3"
        end
        send task_name
      end
    end    
    
    desc <<-DESC
      Overwrite ec2 production database with export from local production database.
    DESC
    task :local_to_ec2 do
      require 'yaml'      
      master_instances = rubber_instances.for_role('db', 'primary' => true)
      slaves = rubber_instances.for_role('db', {})

      # Select only one instance for backup.  Favor slave database.
      selected_db_instance = (slaves+master_instances).first
            
      task_name = "_load_local_to_#{selected_db_instance.full_name}".to_sym()
      task task_name, :hosts => selected_db_instance.full_name do

        # Dump Local to tmp folder
        filename = "#{application}.local.#{Time.now.to_i}.sql.gz" 
        backup_file = "/tmp/#{filename}" 
        on_rollback { delete file }
        FileUtils.mkdir_p(File.dirname(backup_file))

        # Use database.yml to get connection params
        db = YAML::load(ERB.new(IO.read(File.join(File.dirname(__FILE__), '..','database.yml'))).result)[RUBBER_ENV]
        user = db['username']
        pass = db['password']
        pass = nil if pass and pass.strip.size == 0
        host = db['host']
        name = db['database']
        
        raise "No db_backup_cmd defined in rubber.yml, cannot backup!" unless rubber_env.db_backup_cmd
        db_backup_cmd = rubber_env.db_backup_cmd.gsub(/%([^%]+)%/, '#{\1}')
        db_backup_cmd = eval('%Q{' + db_backup_cmd + '}')

        # dbdump (or backup app) needs to be in your path
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
