
redis_host = 'localhost:6379'

resque_yml = Rubber.root.to_s + '/config/resque.yml'
if File.exist? resque_yml
  resque_config = YAML.load_file(resque_yml)
  redis_host = resque_config[Rubber.env]
end

Resque.redis = redis_host
