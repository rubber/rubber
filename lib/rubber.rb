$:.unshift(File.dirname(__FILE__))

require 'monitor'

module Rubber
  extend MonitorMixin

  def self.initialize(project_root, project_env)
    return if defined?(RUBBER_ROOT) && defined?(RUBBER_ENV)

    @config = nil
    @instances = nil

    @@root = project_root
    @@env = project_env
    Object.const_set('RUBBER_ENV', project_env)
    Object.const_set('RUBBER_ROOT', File.expand_path(project_root))

    if ! defined?(Rails) && ! Rubber::Util::is_bundler?
      # pull in basic rails env.  rubber only needs RAILS_ROOT and RAILS_ENV.
      # We actually do NOT want the entire rails environment because it
      # complicates bootstrap (i.e. can't run config to create db because full
      # rails env needs db to exist as some plugin accesses model or something)
      rails_boot_file = File.join(Rubber.root, 'config', 'boot.rb')
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
    Rubber::VERSION
  end

  def self.logger
    @@logger
  end

  def self.config
    unless @config
      synchronize do
        @config ||= Rubber::Configuration.rubber_env
      end
    end

    @config
  end

  def self.instances
    unless @instances
      synchronize do
        @instances ||= Rubber::Configuration.rubber_instances
      end
    end

    @instances
  end
  
  def self.cloud(capistrano = nil)
    # sharing a Net::HTTP instance across threads doesn't work, so
    # create a new instance per thread
    Rubber::ThreadSafeProxy.new { Rubber::Cloud::get_provider(self.config.cloud_provider || "aws", self.config, capistrano) }
  end
  
end

require 'rubber/version'
require 'rubber/platforms'
require 'rubber/thread_safe_proxy'
require 'rubber/configuration'
require 'rubber/environment'
require 'rubber/generator'
require 'rubber/instance'
require 'rubber/util'
require 'rubber/cloud'
require 'rubber/dns'

if defined?(::Vagrant)
  require 'rubber/vagrant/plugin'
end


if defined?(Rails::Railtie)
  module Rubber
    require 'rubber/railtie'
  end
end
