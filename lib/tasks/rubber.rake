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
    log_src_dir = ENV['LOG_DIR'] || raise("No log dir given, try 'LOG_DIR=/foo/log rake rubber:rotate_logs'")
    log_file_glob = ENV['LOG_FILES'] || "*.log"
    log_file_age = ENV['LOG_AGE'].to_i rescue 7

    rotated_date = (Time.now - 86400).strftime('%Y%m%d')
    puts "Rotating logfiles located at: #{log_src_dir}/#{log_file_glob}"
    Dir["#{log_src_dir}/#{log_file_glob}"].each do |logfile|
      sh "cat #{logfile} >> #{logfile}.#{rotated_date}"
      File.truncate logfile, 0
    end

    threshold = Time.now - log_file_age * 86400
    puts "Cleaning rotated log files older than #{log_file_age} days"
    Dir["#{log_src_dir}/#{log_file_glob}.[0-9]*"].each do |logfile|
      if File.mtime(logfile) < threshold
        File.unlink(logfile)
      end
    end
  end


end
