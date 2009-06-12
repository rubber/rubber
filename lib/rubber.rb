$:.unshift(File.dirname(__FILE__))

module Rubber
  VERSION = '0.9.0'
  
  def self.initialize(project_root, project_env)
    Object.const_set('RUBBER_ENV', project_env)
    Object.const_set('PROJECT_ROOT', project_root)

    # pull in basic rails env.  rubber only needs RAILS_ROOT and RAILS_ENV.
    # We actually do NOT want the entire rails environment because it
    # complicates bootstrap (i.e. can't run config to create db because full
    # rails env needs db to exist as some plugin accesses model or something)
    rails_boot_file = File.join(PROJECT_ROOT, 'config', 'boot')
    require(rails_boot_file) if File.exists? rails_boot_file

    if defined?(RAILS_DEFAULT_LOGGER) && RAILS_DEFAULT_LOGGER
      Object.const_set('LOGGER', RAILS_DEFAULT_LOGGER)
    else
      Object.const_set('LOGGER', Logger.new($stdout))
      LOGGER.level = Logger::INFO
      LOGGER.formatter = lambda {|severity, time, progname, msg| "Rubber[%s]: %s\n" % [severity, msg.to_s.lstrip]}
    end
  end
end


require 'rubber/configuration'
require 'rubber/environment'
require 'rubber/generator'
require 'rubber/instance'
require 'rubber/util'
require 'rubber/cloud'
require 'rubber/dns'
