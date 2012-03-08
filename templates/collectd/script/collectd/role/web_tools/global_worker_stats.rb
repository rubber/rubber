require "resque"

redis_server = Rubber.instances.for_role('redis_master').first.full_name rescue nil
redis_server ||= 'localhost' if Rubber.env == 'development'
Resque.redis = "#{redis_server}:6379"

queue_sizes = {}
Resque.redis.smembers("queues").each do |queue_name|
  queue_size = Resque.redis.llen("queue:#{queue_name}")

  puts "PUTVAL #{HOSTNAME}/resque_worker/gauge-#{queue_name}_queued interval=#{INTERVAL} N:#{queue_size}"
end
