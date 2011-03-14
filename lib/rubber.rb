$:.unshift(File.dirname(__FILE__))

module Rubber

  @@version  = File.read(File.join(File.dirname(__FILE__), '..', 'VERSION')).chomp

  def self.initialize(project_root, project_env)
    return if defined?(RUBBER_ROOT) && defined?(RUBBER_ENV)

    @@root = project_root
    @@env = project_env
    Object.const_set('RUBBER_ENV', project_env)
    Object.const_set('RUBBER_ROOT', File.expand_path(project_root))

    if ! defined?(Rails) && ! Rubber::Util::is_bundler?
      # pull in basic rails env.  rubber only needs RAILS_ROOT and RAILS_ENV.
      # We actually do NOT want the entire rails environment because it
      # complicates bootstrap (i.e. can't run config to create db because full
      # rails env needs db to exist as some plugin accesses model or something)
      rails_boot_file = File.join(RUBBER_ROOT, 'config', 'boot.rb')
      require(rails_boot_file) if File.exists? rails_boot_file
    end

    if defined?(Rails.logger) && Rails.logger
      @@logger = Rails.logger
    else
      @@logger = Logger.new($stdout)
      @@logger.level = Logger::INFO
      @@logger.formatter = lambda {|severity, time, progname, msg| "Rubber[%s]: %s\n" % [severity, msg.to_s.lstrip]}
    end

    # conveniences for backwards compatibility with old names
    Object.const_set('RUBBER_CONFIG', self.config)
    Object.const_set('RUBBER_INSTANCES', self.instances)

  end

  def self.root
    @@root
  end

  def self.env
    @@env
  end

  def self.version
    @@version
  end

  def self.logger
    @@logger
  end

  def self.config
    Rubber::Configuration.rubber_env
  end

  def self.instances
    Rubber::Configuration.rubber_instances
  end
end


require 'rubber/thread_safe_proxy'
require 'rubber/configuration'
require 'rubber/environment'
require 'rubber/generator'
require 'rubber/instance'
require 'rubber/util'
require 'rubber/cloud'
require 'rubber/dns'

if Rubber::Util::is_rails3?
  module Rubber
    require 'rubber/railtie'
  end
end