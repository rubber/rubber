
module Rubber
  module Commands

    class Util < Thor

      namespace :util

      desc "rotate_logs", Rubber::Util.clean_indent( <<-EOS
        Rotate rails app server logfiles.  Should be run right after midnight.
      EOS
      )

      method_option :directory,
                    :required => true,
                    :type => :string, :aliases => "-d",
                    :desc => "The directory containing log files to be rotated"
      method_option :pattern,
                    :default => "*.log",
                    :type => :string, :aliases => "-p",
                    :desc => "The glob pattern for matching log files"
      method_option :age,
                    :default => 7,
                    :type => :numeric, :aliases => "-a",
                    :desc => "The number of days rotated log files are kept around for"

      def rotate_logs
        log_src_dir = options.directory
        log_file_glob = options.pattern
        log_file_age = options.age.to_i

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

      desc "backup", Rubber::Util.clean_indent(<<-EOS
        Performs a cyclical backup by storing the results of COMMAND to the backup directory (and s3)
      EOS
      )

      method_option :command,
                    :required => true,
                    :type => :string, :aliases => "-c",
                    :desc => "The command used to extract the data to be backed up"
      method_option :directory,
                    :required => true,
                    :type => :string, :aliases => "-d",
                    :desc => "The directory to stage the backups into"
      method_option :name,
                    :required => true,
                    :type => :string, :aliases => "-n",
                    :desc => "What to name the backup"
      method_option :age,
                    :default => 3,
                    :type => :numeric, :aliases => "-a",
                    :desc => "The number of days rotated backups are kept around for"
      def backup
        dir = options.directory
        name = options.name
        cmd = options.command
        age = options.age.to_i

        time_stamp = Time.now.strftime("%Y-%m-%d_%H-%M")
        FileUtils.mkdir_p(dir)

        backup_cmd = cmd.gsub(/%([^%]+)%/, '#{\1}')
        backup_cmd = eval('%Q{' + backup_cmd + '}')

        puts "Backing up with command:"
        sh backup_cmd
        puts "Backup created"

        s3_prefix = "#{name}/"
        backup_bucket = cloud_provider.backup_bucket
        if backup_bucket
          init_s3
          unless AWS::S3::Bucket.list.find { |b| b.name == backup_bucket }
            AWS::S3::Bucket.create(backup_bucket)
          end
          newest = Dir.entries(dir).grep(/^[^.]/).sort_by {|f| File.mtime(File.join(dir,f))}.last
          dest = "#{s3_prefix}#{newest}"
          puts "Saving backup to S3: #{backup_bucket}:#{dest}"
          AWS::S3::S3Object.store(dest, open(File.join(dir, newest)), backup_bucket)
        end

        tdate = Date.today - age
        threshold = Time.local(tdate.year, tdate.month, tdate.day)
        puts "Cleaning backups older than #{age} days"
        Dir["#{dir}/*"].each do |file|
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

      desc "backup_db", <<-DESC
        Backup database to given backup directory
        The following arguments affect behavior:
        BACKUP_DIR (required): Directory where db backups will be stored
        BACKUP_AGE (3):        Delete rotated logs older than this many days in the past
        DBUSER (required)      User to connect to the db as
        DBPASS (optional):     Pass to connect to the db with
        DBHOST (required):     Host where the db is
        DBNAME (required):     Database name to backup
      DESC
      def backup_db
        options[''] =
        dir = get_env('BACKUP_DIR', true)
        age = (get_env('BACKUP_AGE') || 3).to_i
        time_stamp = Time.now.strftime("%Y-%m-%d_%H-%M")
        backup_file = "#{dir}/#{RUBBER_ENV}_dump_#{time_stamp}.sql.gz"
        FileUtils.mkdir_p(File.dirname(backup_file))

        user = options.user
        pass = options.password
        host = options.host
        name = options.db
        options.command = db_backup_cmd
        raise "No db_backup_cmd defined in rubber.yml, cannot backup!" unless rubber_env.db_backup_cmd
        db_backup_cmd = rubber_env.db_backup_cmd.gsub(/%([^%]+)%/, '#{\1}')
        db_backup_cmd = eval('%Q{' + db_backup_cmd + '}')

        puts "Backing up database with command:"
        sh db_backup_cmd
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
        Dir["#{dir}/*"].each do |file|
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

      
      protected

      
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
        AWS::S3::Base.establish_connection!(:access_key_id => cloud_provider.access_key, :secret_access_key => cloud_provider.secret_access_key)
      end

    end

  end
end
