
module Rubber
  module Commands

    module Support
      
      def rubber_env()
        Rubber::Configuration.rubber_env
      end
      
      def rubber_instances()
        Rubber::Configuration.rubber_instances
      end
      
      def cloud_provider
        rubber_env.cloud_providers[rubber_env.cloud_provider]
      end
      
      def init_s3()
        AWS::S3::Base.establish_connection!(:access_key_id => cloud_provider.access_key,
                                            :secret_access_key => cloud_provider.secret_access_key)
      end
      
    end
  
    class RotateLogs < Clamp::Command
      include Rubber::Commands::Support
      
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
      include Rubber::Commands::Support
      
      def self.subcommand_name
        "util:backup"
      end

      def self.subcommand_description
        "Performs a cyclical backup"
      end
      
      def self.description
        "Performs a cyclical backup by storing the results of COMMAND to the backup\ndirectory (and s3)"
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

        FileUtils.mkdir_p(directory)
      
        backup_cmd = command.gsub(/%([^%]+)%/, '#{\1}')
        backup_cmd = eval('%Q{' + backup_cmd + '}')
      
        puts "Backing up with command: '#{backup_cmd}'"
        system backup_cmd || fail("Command failed: '#{backup_cmd.inspect}'")
        puts "Backup created"
      
        s3_prefix = "#{name}/"
        backup_bucket = cloud_provider.backup_bucket
        if backup_bucket
          init_s3
          unless AWS::S3::Bucket.list.find { |b| b.name == backup_bucket }
            AWS::S3::Bucket.create(backup_bucket)
          end
          newest = Dir.entries(directory).grep(/^[^.]/).sort_by {|f| File.mtime(File.join(directory,f))}.last
          dest = "#{s3_prefix}#{newest}"
          puts "Saving backup to S3: #{backup_bucket}:#{dest}"
          AWS::S3::S3Object.store(dest, open(File.join(directory, newest)), backup_bucket)
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
          puts "Cleaning S3 backups older than #{age} days from: #{backup_bucket}:#{s3_prefix}"
          AWS::S3::Bucket.objects(backup_bucket, :prefix => s3_prefix).clone.each do |obj|
            if Time.parse(obj.about["last-modified"]) < threshold
              puts "Deleting #{obj.key}"
              obj.delete
            end
          end
        end
      end
      
    end
  
    class BackupDb < Clamp::Command
      include Rubber::Commands::Support
      
      def self.subcommand_name
        "util:backup_db"
      end

      def self.subcommand_description
        "Performs a cyclical database backup"
      end
      
      def self.description
        Rubber::Util.clean_indent( <<-EOS
          Performs a cyclical backup of the database by storing the results of COMMAND
          to the backup directory (and s3)
        EOS
        )
      end
      
      option ["-d", "--directory"],
             "DIRECTORY",
             "The directory to stage backups into\nRequired"
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
        backup_file = "#{directory}/#{RUBBER_ENV}_dump_#{time_stamp}.sql.gz"
        FileUtils.mkdir_p(File.dirname(backup_file))
        
        # extra variables for command interpolation
        dir = directory
        user = dbuser
        pass = dbpass
        pass = nil if pass && pass.strip.size == 0
        host = dbhost
        name = dbname
      
        raise "No db_backup_cmd defined in rubber.yml, cannot backup!" unless rubber_env.db_backup_cmd
        db_backup_cmd = rubber_env.db_backup_cmd.gsub(/%([^%]+)%/, '#{\1}')
        db_backup_cmd = eval('%Q{' + db_backup_cmd + '}')
      
        puts "Backing up database with command: '#{db_backup_cmd}'"
        system db_backup_cmd || fail("Command failed: '#{db_backup_cmd.inspect}'")
        puts "Created backup: #{backup_file}"
      
        s3_prefix = "db/"
        backup_bucket = cloud_provider.backup_bucket
        if backup_bucket
          init_s3
          unless AWS::S3::Bucket.list.find { |b| b.name == backup_bucket }
            AWS::S3::Bucket.create(backup_bucket)
          end
          dest = "#{s3_prefix}#{File.basename(backup_file)}"
          puts "Saving db backup to S3: #{backup_bucket}:#{dest}"
          AWS::S3::S3Object.store(dest, open(backup_file), backup_bucket)
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
          puts "Cleaning S3 backups older than #{age} days from: #{backup_bucket}:#{s3_prefix}"
          AWS::S3::Bucket.objects(backup_bucket, :prefix => s3_prefix).clone.each do |obj|
            if Time.parse(obj.about["last-modified"]) < threshold
              puts "Deleting #{obj.key}"
              obj.delete
            end
          end
        end
        
      end

    end
  
    class RestoreDbS3 < Clamp::Command
      include Rubber::Commands::Support
      
      def self.subcommand_name
        "util:restore_db_s3"
      end

      def self.subcommand_description
        "Performs a restore of the database from s3"
      end
      
      option ["-f", "--filename"],
             "FILENAME",
             "The key of S3 object to use\nMost recent if not supplied"
      option ["-u", "--dbuser"],
             "DBUSER",
             "The database user to connect with\nRequired"
      option ["-p", "--dbpass"],
             "DBUSER",
             "The database password to connect with"
      option ["-h", "--dbhost"],
             "DBHOST",
             "The database host to connect to\nRequired"

      def execute
        signal_usage_error "DBUSER, DBHOST are required" unless dbuser && dbhost

        # extra variables for command interpolation
        file = filename
        user = dbuser
        pass = dbpass
        pass = nil if pass && pass.strip.size == 0
        host = dbhost
      
        raise "No db_restore_cmd defined in rubber.yml" unless rubber_env.db_restore_cmd
        db_restore_cmd = rubber_env.db_restore_cmd.gsub(/%([^%]+)%/, '#{\1}')
        db_restore_cmd = eval('%Q{' + db_restore_cmd + '}')
      
        # try to fetch a matching file from s3 (if backup_bucket given)
        backup_bucket = cloud_provider.backup_bucket
        raise "No backup_bucket defined in rubber.yml" unless backup_bucket
        if (init_s3 &&
            AWS::S3::Bucket.list.find { |b| b.name == backup_bucket })
          s3objects = AWS::S3::Bucket.find(backup_bucket,
                     :prefix => 'db/')
          if filename
            puts "trying to fetch #{filename} from s3"
            data = s3objects.detect { |o| filename == o.key }
          else
            puts "trying to fetch last modified s3 backup"
            data = s3objects.max {|a,b| a.about["last-modified"] <=> b.about["last-modified"] }
          end
        end
        raise "could not access backup file via s3" unless data
      
        puts "piping restore data to command [#{db_restore_cmd}]"
        IO.popen(db_restore_cmd, 'wb') do |p|
          data.value do |segment|
            p.write segment
          end
        end
      
      end
      
    end
      
  end
end
