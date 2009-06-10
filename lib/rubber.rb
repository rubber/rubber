$:.unshift(File.dirname(__FILE__))

require 'rubber/configuration'
require 'rubber/environment'
require 'rubber/generator'
require 'rubber/instance'
require 'rubber/util'
require 'rubber/cloud'
require 'rubber/dns'

# pull in basic rails env.  rubber only needs RAILS_ROOT and RAILS_ENV.
# We actually do NOT want the entire rails environment because it
# complicates bootstrap (i.e. can't run config to create db because full
# rails env needs db to exist as some plugin accesses model or something)
PROJECT_ROOT ||= ENV['PROJECT_ROOT'] ||= RAILS_ROOT

rails_boot_file = File.join(File.dirname(__FILE__), 'config', 'boot')
require(rails_boot_file) if File.exists? rails_boot_file

RUBBER_ENV ||= ENV['RUBBER_ENV'] ||= ENV['RAILS_ENV'] ||= 'development'

if defined?(RAILS_DEFAULT_LOGGER) && RAILS_DEFAULT_LOGGER
  LOGGER = RAILS_DEFAULT_LOGGER
else
  LOGGER = Logger.new($stdout)
  LOGGER.level = Logger::INFO
  LOGGER.formatter = lambda {|severity, time, progname, msg| "Rubber[%s]: %s\n" % [severity, msg.to_s.lstrip]}
end


module Rubber
  VERSION = '0.9.0'
end
