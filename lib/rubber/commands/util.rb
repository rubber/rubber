require 'date'

module Rubber
  module Commands

    class RotateLogs < Clamp::Command
      
      def self.subcommand_name
        "util:rotate_logs"
      end

      def self.subcommand_description
        "Rotate the matching log files"
      end
      
      option ["-d", "--directory"],
             "DIRECTORY",
             "The directory containing files to be rotated\nRequired"
      option ["-p", "--pattern"],
             "PATTERN",
             "The glob pattern for matching files\n",
             :default => "*.log"
      option ["-a", "--age"],
             "AGE",
             "The number of days to keep rotated files\n",
             :default => 7,
             &Proc.new {|a| Integer(a)}

      def execute
        signal_usage_error "DIRECTORY is required" unless directory
        
        log_src_dir = directory
        log_file_glob = pattern
        log_file_age = age

        rotated_date = (Date.today - 1).strftime('%Y%m%d')
        puts "Rotating logfiles located at: #{log_src_dir}/#{log_file_glob}"
        Dir["#{log_src_dir}/#{log_file_glob}"].each do |logfile|
          rotated_file = "#{logfile}.#{rotated_date}"
          if File.exist?(rotated_file)
            rotated_file += "_#{Time.now.to_i}"
          end
          FileUtils.cp(logfile, rotated_file)
          File.truncate logfile, 0
        end

        tdate = Date.today - log_file_age
        threshold = Time.local(tdate.year, tdate.month, tdate.day)
        puts "Cleaning rotated log files older than #{log_file_age} days"
        Dir["#{log_src_dir}/#{log_file_glob}.[0-9]*"].each do |logfile|
          if File.mtime(logfile) < threshold
            FileUtils.rm_f(logfile)
          end
        end
      end

    end
      
    class Backup < Clamp::Command
      
      def self.subcommand_name
        "util:backup"
      end

      def self.subcommand_description
        "Performs a cyclical backup"
      end
      
      def self.description
        "Performs a cyclical backup by storing the results of COMMAND to the backup\ndirectory (and the cloud)"
      end
      
      option ["-n", "--name"],
             "NAME",
             "What to name the backup\nRequired"
      option ["-d", "--directory"],
             "DIRECTORY",
             "The directory to stage backups into\nRequired"
      option ["-c", "--command"],
             "COMMAND",
             "The command used to extract the data to be\nbacked up\nRequired"
      option ["-a", "--age"],
             "AGE",
             "The number of days to keep rotated files\n",
             :default => 7,
             &Proc.new {|a| Integer(a)}

      def execute
        signal_usage_error "NAME, DIRECTORY and COMMAND are required" unless name && directory && command
        
        # extra variables for command interpolation
        time_stamp = Time.now.strftime("%Y-%m-%d_%H-%M")
        dir = directory
        
        # differentiate by env
        cloud_prefix = "#{name}/"
        self.name = "#{Rubber.env}_#{self.name}"

        FileUtils.mkdir_p(directory)
      
        backup_cmd = command.gsub(/%([^%]+)%/, '#{\1}')
        backup_cmd = eval('%Q{' + backup_cmd + '}')
      
        puts "Backing up with command: '#{backup_cmd}'"
        system backup_cmd || fail("Command failed: '#{backup_cmd.inspect}'")
        puts "Backup created"
      
        backup_bucket = Rubber.cloud.env.backup_bucket
        if backup_bucket
          newest = Dir.entries(directory).grep(/^[^.]/).sort_by {|f| File.mtime(File.join(directory,f))}.last
          dest = "#{cloud_prefix}#{newest}"
          puts "Saving backup to cloud: #{backup_bucket}:#{dest}"
          Rubber.cloud.storage(backup_bucket).store(dest, open(File.join(directory, newest)))
        end
      
        tdate = Date.today - age
        threshold = Time.local(tdate.year, tdate.month, tdate.day)
        puts "Cleaning backups older than #{age} days"
        Dir["#{directory}/*"].each do |file|
          if File.mtime(file) < threshold
            puts "Deleting #{file}"
            FileUtils.rm_f(file)
          end
        end
      
        if backup_bucket
          puts "Cleaning cloud backups older than #{age} days from: #{backup_bucket}:#{cloud_prefix}"
          Rubber.cloud.storage(backup_bucket).walk_tree(cloud_prefix) do |f|
            if f.last_modified < threshold
              puts "Deleting #{f.key}"
              f.destroy
            end
          end
        end
      end
      
    end
  
    class BackupDb < Clamp::Command
      
      def self.subcommand_name
        "util:backup_db"
      end

      def self.subcommand_description
        "Performs a cyclical database backup"
      end
      
      def self.description
        Rubber::Util.clean_indent( <<-EOS
          Performs a cyclical backup of the database by storing the results of COMMAND
          to the backup directory (and the cloud)
        EOS
        )
      end
      
      option ["-d", "--directory"],
             "DIRECTORY",
             "The directory to stage backups into\nRequired"
      option ["-f", "--filename"],
             "FILENAME",
             "The name of the backup file"
      option ["-u", "--dbuser"],
             "DBUSER",
             "The database user to connect with\nRequired"
      option ["-p", "--dbpass"],
             "DBUSER",
             "The database password to connect with"
      option ["-h", "--dbhost"],
             "DBHOST",
             "The database host to connect to\nRequired"
      option ["-n", "--dbname"],
             "DBNAME",
             "The database name to backup\nRequired"
      option ["-a", "--age"],
             "AGE",
             "The number of days to keep rotated files\n",
             :default => 7,
             &Proc.new {|a| Integer(a)}

      def execute
        signal_usage_error "DIRECTORY, DBUSER, DBHOST, DBNAME are required" unless directory && dbuser && dbhost && dbname
        
        time_stamp = Time.now.strftime("%Y-%m-%d_%H-%M")
        if filename
          backup_file = "#{directory}/#{filename}"
        else
          backup_file = "#{directory}/#{Rubber.env}_dump_#{time_stamp}.sql.gz"
        end
        FileUtils.mkdir_p(File.dirname(backup_file))
        
        # extra variables for command interpolation
        dir = directory
        user = dbuser
        pass = dbpass
        pass = nil if pass && pass.strip.size == 0
        host = dbhost
        name = dbname
      
        raise "No db_backup_cmd defined in rubber.yml, cannot backup!" unless Rubber.config.db_backup_cmd
        db_backup_cmd = Rubber.config.db_backup_cmd.gsub(/%([^%]+)%/, '#{\1}')
        db_backup_cmd = eval('%Q{' + db_backup_cmd + '}')
      
        puts "Backing up database with command: '#{db_backup_cmd}'"
        system db_backup_cmd || fail("Command failed: '#{db_backup_cmd.inspect}'")
        puts "Created backup: #{backup_file}"
      
        cloud_prefix = "db/"
        backup_bucket = Rubber.cloud.env.backup_bucket
        if backup_bucket
          dest = "#{cloud_prefix}#{File.basename(backup_file)}"
          puts "Saving db backup to cloud: #{backup_bucket}:#{dest}"
          Rubber.cloud.storage(backup_bucket).store(dest, open(backup_file))
        end
      
        tdate = Date.today - age
        threshold = Time.local(tdate.year, tdate.month, tdate.day)
        puts "Cleaning backups older than #{age} days"
        Dir["#{directory}/*"].each do |file|
          if file =~ /#{Rubber.env}_dump_/ && File.mtime(file) < threshold
            puts "Deleting #{file}"
            FileUtils.rm_f(file)
          end
        end
      
        if backup_bucket
          puts "Cleaning cloud backups older than #{age} days from: #{backup_bucket}:#{cloud_prefix}"
          Rubber.cloud.storage(backup_bucket).walk_tree(cloud_prefix) do |f|
            if f.key =~ /#{Rubber.env}_dump_/ && f.last_modified < threshold
              puts "Deleting #{f.key}"
              f.destroy
            end
          end
        end
        
      end

    end
  
    class RestoreDb < Clamp::Command
      
      def self.subcommand_name
        "util:restore_db"
      end

      def self.subcommand_description
        "Performs a restore of the database"
      end
      
      option ["-f", "--filename"],
             "FILENAME",
             "The key of cloud object to use\nMost recent if not supplied"
      option ["-u", "--dbuser"],
             "DBUSER",
             "The database user to connect with\nRequired"
      option ["-p", "--dbpass"],
             "DBPASS",
             "The database password to connect with"
      option ["-h", "--dbhost"],
             "DBHOST",
             "The database host to connect to\nRequired"
      option ["-n", "--dbname"],
             "DBNAME",
             "The database name to backup\nRequired"

      def execute
        signal_usage_error "DBUSER, DBHOST are required" unless dbuser && dbhost

        # extra variables for command interpolation
        file = filename
        user = dbuser
        pass = dbpass
        pass = nil if pass && pass.strip.size == 0
        host = dbhost
        name = dbname
      
        raise "No db_restore_cmd defined in rubber.yml" unless Rubber.config.db_restore_cmd
        db_restore_cmd = Rubber.config.db_restore_cmd.gsub(/%([^%]+)%/, '#{\1}')
        db_restore_cmd = eval('%Q{' + db_restore_cmd + '}')
      
        # try to fetch a matching file from the cloud (if backup_bucket given)
        backup_bucket = Rubber.cloud.env.backup_bucket
        raise "No backup_bucket defined in rubber.yml" unless backup_bucket
        
        key = nil
        cloud_prefix = "db/"
        if filename
          key = "#{cloud_prefix}#{filename}"
        else
          puts "trying to fetch last modified cloud backup"
          max = nil
          Rubber.cloud.storage(backup_bucket).walk_tree(cloud_prefix) do |f|
            if f.key =~ /#{Rubber.env}_dump_/
              max = f if max.nil? || f.last_modified > max.last_modified
            end
          end
          key = max.key if max
        end
        
        raise "could not access backup file from cloud" unless key
      
        puts "piping restore data from #{backup_bucket}:#{key} to command [#{db_restore_cmd}]"
        
        IO.popen(db_restore_cmd, 'wb') do |p|
          Rubber.cloud.storage(backup_bucket).fetch(key) do |chunk|
            p.write chunk
          end
        end
      
      end
      
    end

    class Obfuscation < Clamp::Command
      
      def self.subcommand_name
        "util:obfuscation"
      end

      def self.subcommand_description
        "Obfuscates rubber-secret.yml using encryption"
      end
      
      option ["-f", "--secretfile"],
             "SECRETFILE",
             "The rubber_secret file\n (default: <Rubber.config.rubber_secret>)"
      
      option ["-k", "--secretkey"],
             "SECRETKEY",
             "The rubber_secret_key\n (default: <Rubber.config.rubber_secret_key>)"
      
      option ["-d", "--decrypt"],
             :flag,
             "Decrypt and display the current rubber_secret"

      option ["-g", "--generate"],
             :flag,
             "Generate a key for rubber_secret_key"

      def execute
        require 'rubber/encryption'

        if generate?
          puts "Obfuscation key: " + Rubber::Encryption.generate_encrypt_key.inspect
          exit
        else
          signal_usage_error "Need to define a rubber_secret in rubber.yml" unless secretfile
          signal_usage_error "Need to define a rubber_secret_key in rubber.yml" unless secretkey
          signal_usage_error "The file pointed to by rubber_secret needs to exist" unless File.exist?(secretfile)
          data = IO.read(secretfile)
          
          if decrypt?
            puts Rubber::Encryption.decrypt(data, secretkey)
          else
            puts Rubber::Encryption.encrypt(data, secretkey)
          end
        end
      end

    end
    
  end
end
