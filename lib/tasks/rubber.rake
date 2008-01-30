require 'fileutils'

namespace :rubber do

  if ENV['NO_ENV']
    $:.unshift "#{File.dirname(__FILE__)}/.."
  end

  desc "Generate system config files by transforming the files in the config tree"
  task :config => ENV['NO_ENV'] ? [] : [:environment] do
    require 'socket'
    instance_alias = Socket::gethostname.gsub(/\..*/, '')

    require 'rubber/configuration'
    cfg = Rubber::Configuration.get_configuration(ENV['RAILS_ENV'])
    instance = cfg.instance[instance_alias]
    if instance
      roles = instance.roles.collect{|role| role.name}
    elsif RAILS_ENV == 'development'
      roles = cfg.environment.known_roles
      instance = Rubber::Configuration::InstanceItem.new(instance_alias, roles, nil)
      cfg.instance.add(instance)
    end

    gen = Rubber::Configuration::Generator.new('config/rubber', roles, instance_alias)
    if ENV['NO_POST']
      gen.no_post = true
    end
    if ENV['FILE']
      gen.file_pattern = ENV['FILE']
    end
    gen.run

  end

  desc <<-DESC
    Rotate rails app server logfiles.  Should be run right after midnight.
    The following arguments affect behavior:
    LOG_DIR (required): Directory where log files are located
    LOG_FILE (*.log):   File pattern to match to find logs to rotate
    LOG_AGE (7):        Delete rotated logs older than this many days in the past
  DESC
  task :rotate_logs do
    log_src_dir = get_env('LOG_DIR', true)
    log_file_glob = get_env('LOG_FILES') || "*.log"
    log_file_age = (get_env('LOG_AGE') || 7).to_i

    rotated_date = (Time.now - 86400).strftime('%Y%m%d')
    puts "Rotating logfiles located at: #{log_src_dir}/#{log_file_glob}"
    Dir["#{log_src_dir}/#{log_file_glob}"].each do |logfile|
      rotated_file = "#{logfile}.#{rotated_date}"
      FileUtils.cp(logfile, rotated_file)
      File.truncate logfile, 0
    end

    threshold = Time.now - log_file_age * 86400
    puts "Cleaning rotated log files older than #{log_file_age} days"
    Dir["#{log_src_dir}/#{log_file_glob}.[0-9]*"].each do |logfile|
      if File.mtime(logfile) < threshold
        FileUtils.rm_f(logfile)
      end
    end
  end

  desc <<-DESC
    Backup database to s3
    The following arguments affect behavior:
    BACKUP_DIR (required): Directory where db backups will be stored
    BACKUP_AGE (7):        Delete rotated logs older than this many days in the past
    DBUSER (required)      User to connect to the db as
    DBPASS (optional):     Pass to connect to the db with
    DBHOST (required):     Host where the db is
    DBNAME (required):     Database name to backup
  DESC
  task :backup_db do
    dir = get_env('BACKUP_DIR', true)
    age = (get_env('BACKUP_AGE') || 3).to_i
    time_stamp = Time.now.strftime("%Y-%m-%d_%H-%M")
    backup_file = "#{dir}/#{RAILS_ENV}_dump_#{time_stamp}.sql.gz"
    FileUtils.mkdir_p(File.dirname(backup_file))

    user = get_env('DBUSER', true)
    pass = get_env('DBPASS')
    host = get_env('DBHOST', true)
    name = get_env('DBNAME', true)
    sh "nice mysqldump -h #{host} -u #{user} #{'-p' + pass if pass} #{name} | gzip -c > #{backup_file}"
    puts "Created backup: #{backup_file}"

    threshold = Time.now - age * 86400
    puts "Cleaning backups older than #{age} days"
    Dir["#{dir}/*"].each do |file|
      if File.mtime(file) < threshold
        FileUtils.rm_f(file)
      end
    end
  end

  def get_env(name, required=false)
    value = ENV[name]
    raise("#{name} is required, pass using environment") if required && ! value
    return value
  end

end
