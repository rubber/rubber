
redis_host = 'localhost:6379'

resque_yml = Rubber.root.to_s + '/config/resque.yml'
if File.exist? resque_yml
  resque_config = YAML.load_file(resque_yml)
  redis_host = resque_config[Rubber.env]
end

Resque.redis = redis_host

# The schedule doesn't need to be stored in a YAML, it just needs to
# be a hash.  YAML is usually the easiest.
schedule_yml = Rubber.root.to_s + '/config/resque_schedule.yml'
Resque.schedule = YAML.load_file(schedule_yml) if File.exist?(schedule_yml)
