require 'redis'

redis = Redis.new(:host => 'localhost', :port => 6379, :timeout => INTERVAL - 1)
info = redis.info

items = {
  'connected_clients' => 'gauge',
  'client_longest_output_list' => 'gauge',
  'client_biggest_input_buf' => 'gauge',
  'blocked_clients' => 'gauge',
  'total_commands_processed' => 'derive',
  'total_connections_received' => 'derive',
  'connected_clients' => 'gauge',
  'used_memory' => 'gauge',
  'changes_since_last_save' => 'gauge'
}

items.each do |item, ctype|
  puts "PUTVAL #{HOSTNAME}/redis/#{ctype}-#{item} interval=#{INTERVAL} N:#{info[item]}"
end

info.keys.grep(/^db[0-9]+/).each do |key|
  data = info[key]
  if data =~ /keys=(\d+),expires=(\d+)/
    puts "PUTVAL #{HOSTNAME}/redis/gauge-keys_#{key} interval=#{INTERVAL} N:#{$1}"
    puts "PUTVAL #{HOSTNAME}/redis/gauge-expires_#{key} interval=#{INTERVAL} N:#{$2}"
  end
end
