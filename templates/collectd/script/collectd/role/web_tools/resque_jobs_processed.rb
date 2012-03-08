require "resque"

redis_server = Rubber.instances.for_role('redis_master').first.full_name rescue nil
redis_server ||= 'localhost' if Rubber.env == 'development'
Resque.redis = "#{redis_server}:6379"

puts "PUTVAL #{HOSTNAME}/resque/derive-jobs_processed interval=#{INTERVAL} N:#{Resque.redis.get("stat:processed").to_i}"
puts "PUTVAL #{HOSTNAME}/resque/derive-jobs_failed interval=#{INTERVAL} N:#{Resque.redis.get("stat:failed").to_i}"
