namespace :rubber do
  namespace :util do
  
    rubber.allow_optional_tasks(self)
   
    desc <<-DESC
      Backup database using rubber util:backup_db
    DESC
    task :backup do
      master_instances = rubber_instances.for_role('db', 'primary' => true)
      slaves = rubber_instances.for_role('db', {})

      # Select only one instance for backup.  Favor slave database.
      selected_db_instance = (slaves+master_instances).first
            
      task_name = "_backup_db_#{selected_db_instance.full_name}".to_sym()
      task task_name, :hosts => selected_db_instance.full_name do
        rsudo "cd #{current_path} && RUBBER_ENV=#{Rubber.env} ./script/rubber util:backup_db --directory=/mnt/db_backups --dbuser=#{rubber_env.db_user} --dbpass=#{rubber_env.db_pass} --dbname=#{rubber_env.db_name} --dbhost=#{selected_db_instance.full_name}"
      end
      send task_name
    end
    
    desc <<-DESC
      Restore database from cloud using rubber util:restore_db
    DESC
    task :restore_cloud do
      filename = get_env('FILENAME', "The cloud key to restore", true)
      master_instances = rubber_instances.for_role('db', 'primary' => true)
      slaves = rubber_instances.for_role('db', {})

      for instance in master_instances+slaves
        task_name = "_restore_db_cloud_#{instance.full_name}".to_sym()
        task task_name, :hosts => instance.full_name do
          rsudo "cd #{current_path} && RUBBER_ENV=#{Rubber.env} ./script/rubber util:restore_db --filename=#{filename} --dbuser=#{rubber_env.db_user} --dbpass=#{rubber_env.db_pass} --dbname=#{rubber_env.db_name} --dbhost=#{instance.full_name}"
        end
        send task_name
      end
    end    
    
    desc <<-DESC
      Overwrite production database with export from local production database.
    DESC
    task :local_to_cloud do
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
        db = YAML::load(ERB.new(IO.read(File.join(File.dirname(__FILE__), '..','database.yml'))).result)[Rubber.env]
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

        # Upload Local to Cloud
        backup_bucket = Rubber.cloud.env.backup_bucket
        dest = "db/#{File.basename(backup_file)}"
          
        puts "Saving db dump to cloud: #{backup_bucket}:#{dest}"
        Rubber.cloud.storage(backup_bucket).store(dest, open(backup_file))
        
        send :restore_cloud

      end
      send task_name
    end    

  end
end
