# rails tries to load this from generator dir, so skip it.
if __FILE__ !~ /rubber\/generators\/vulcanize/

  env = ENV['RUBBER_ENV'] ||= (ENV['RAILS_ENV'] || 'development')
  root = File.dirname(__FILE__) + '/../..'

  # this tries first as a rails plugin then as a gem
  $:.unshift "#{root}/vendor/plugins/rubber/lib/"
  require 'rubber'

  Rubber::initialize(root, env)

  require 'rubber/tasks/rubber'

end
