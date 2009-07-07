# rails tries to load this from generator dir, so skip it.
if __FILE__ !~ /rubber\/generators\/vulcanize/

  begin
    # first try as a rails plugin
    require "#{File.dirname(__FILE__)}/../../vendor/plugins/rubber/lib/rubber.rb"
  rescue LoadError
    # then try as a gem
    require 'rubber'
  end

  env = ENV['RUBBER_ENV'] ||= (ENV['RAILS_ENV'] || 'development')
  root = File.dirname(__FILE__) + '/../..'
  Rubber::initialize(root, env)

  require 'rubber/tasks/rubber'

end
