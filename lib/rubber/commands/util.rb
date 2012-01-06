
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
        system backup_cmd || fail("Command failed: #{backup_cmd.inspect}")
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

      desc "backup_db", Rubber::Util.clean_indent(<<-EOS
        Performs a cyclical backup of the database to the backup directory (and s3)
      EOS
      )

      method_option :directory,
                    :required => true,
                    :type => :string, :aliases => "-d",
                    :desc => "The directory to stage the backups into"
      method_option :age,
                    :default => 3,
                    :type => :numeric, :aliases => "-a",
                    :desc => "The number of days rotated backups are kept around for"
      method_option :dbuser,
                    :required => true,
                    :type => :string, :aliases => "-u",
                    :desc => "The database user to connect with"
      method_option :dbpass,
                    :required => false,
                    :type => :string, :aliases => "-p",
                    :desc => "The database password to connect with"
      method_option :dbhost,
                    :required => true,
                    :type => :string, :aliases => "-h",
                    :desc => "The database host to connect to"
      method_option :dbname,
                    :required => true,
                    :type => :string, :aliases => "-n",
                    :desc => "The database name to backup"

      def backup_db
        dir = options.directory
        age = options.age.to_i

        time_stamp = Time.now.strftime("%Y-%m-%d_%H-%M")
        backup_file = "#{dir}/#{RUBBER_ENV}_dump_#{time_stamp}.sql.gz"
        FileUtils.mkdir_p(File.dirname(backup_file))

        user = options.dbuser
        pass = options.dbpass
        pass = nil if pass && pass.strip.size == 0
        host = options.dbhost
        name = options.dbname

        raise "No db_backup_cmd defined in rubber.yml, cannot backup!" unless rubber_env.db_backup_cmd
        db_backup_cmd = rubber_env.db_backup_cmd.gsub(/%([^%]+)%/, '#{\1}')
        db_backup_cmd = eval('%Q{' + db_backup_cmd + '}')

        puts "Backing up database with command:"
        system db_backup_cmd || fail("Command failed: #{db_backup_cmd.inspect}")
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

      desc "restore_db_s3", Rubber::Util.clean_indent(<<-EOS
        Performs a restore of the database from the given file
      EOS
      )

      method_option :filename,
                    :required => true,
                    :type => :string, :aliases => "-f",
                    :desc => "key of S3 object to use"
      method_option :dbuser,
                    :required => true,
                    :type => :string, :aliases => "-u",
                    :desc => "The database user to connect with"
      method_option :dbpass,
                    :required => false,
                    :type => :string, :aliases => "-p",
                    :desc => "The database password to connect with"
      method_option :dbhost,
                    :required => true,
                    :type => :string, :aliases => "-h",
                    :desc => "The database host to connect to"
      method_option :dbname,
                    :required => true,
                    :type => :string, :aliases => "-n",
                    :desc => "The database name to backup"

      def restore_db_s3
        file = options.filename
        user = options.dbuser
        pass = options.dbpass
        pass = nil if pass && pass.strip.size == 0
        host = options.dbhost

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
          if file
            puts "trying to fetch #{file} from s3"
            data = s3objects.detect { |o| file == o.key }
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
