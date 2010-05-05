require 'yaml'
require 'resque'

rails_root = ENV['RAILS_ROOT'] || File.dirname(__FILE__) + '/../..'
rails_env = ENV['RAILS_ENV'] || 'development'

redis_host = 'localhost:6379'

resque_yml = rails_root + '/config/resque.yml'
if File.exist? resque_yml
  resque_config = YAML.load_file(resque_yml)
  redis_host = resque_config[rails_env]
end

Resque.redis = redis_host
