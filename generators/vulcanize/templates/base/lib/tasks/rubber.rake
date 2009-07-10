# rails tries to load this from generator dir, so skip it.
if __FILE__ !~ /rubber\/generators\/vulcanize/

  begin
    # first try as a gem
    require 'rubber'
  rescue LoadError
    # then try as a rails plugin
    $:.unshift "#{File.dirname(__FILE__)}/../../vendor/plugins/rubber/lib/"
    require 'rubber'
  end

  env = ENV['RUBBER_ENV'] ||= (ENV['RAILS_ENV'] || 'development')
  root = File.dirname(__FILE__) + '/../..'
  Rubber::initialize(root, env)

  require 'rubber/tasks/rubber'

end
