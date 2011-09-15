
WorkerItem = Struct.new(:pid, :process_type, :target, :start_time)

idle = []
starting = []
paused = []
parents = []
children = []

data = `ps ax | grep '[r]esque.*:'`
data.lines do |line|
  line.chomp!
  cols = line.split

  # 12887 ?        Sl     0:01 resque-1.13.0: Forked 31395 at 1300564431
  # 13054 ?        Sl     0:23 resque-1.13.0: Processing facebook since 1300565337
  # 28561 ?        Sl     0:03 resque-1.13.0: Waiting for *index*

  item = WorkerItem.new
  item.pid = cols[0]
  item.process_type = case cols[5]
    when 'Processing' then :child
    when 'Forked' then :parent
    when 'Waiting' then (cols.delete_at(6); :idle)
    when 'Starting' then :starting
    when 'Paused' then :paused
    else :unknown
  end
  item.target = cols[6]
  item.start_time = cols[8].to_i

  idle << item if item.process_type == :idle
  starting << item if item.process_type == :starting
  paused << item if item.process_type == :paused
  parents << item if item.process_type == :parent
  children << item if item.process_type == :child
end

pairs = {}
[*parents, *children].each {|item| pairs[item.pid] ||= [];  pairs[item.pid] << item}
stuck_parents = pairs.select{|item| item.size == 1 && item.first.type == :parent}
stuck_children = pairs.select{|item| item.size == 1 && item.first.type == :child}

counts = children.group_by {|item| item.target || 'unknown' }

working = counts.values.collect(&:size).inject(0) { |sum, p| sum + p }
utilization = (working.to_f / (working + idle.size + starting.size + paused.size) * 100).to_i rescue 0
puts "PUTVAL #{HOSTNAME}/resque_worker/gauge-working interval=#{INTERVAL} N:#{working}"
puts "PUTVAL #{HOSTNAME}/resque_worker/gauge-utilization interval=#{INTERVAL} N:#{utilization}"
puts "PUTVAL #{HOSTNAME}/resque_worker/gauge-idle interval=#{INTERVAL} N:#{idle.size}"
puts "PUTVAL #{HOSTNAME}/resque_worker/gauge-starting interval=#{INTERVAL} N:#{starting.size}"
puts "PUTVAL #{HOSTNAME}/resque_worker/gauge-paused interval=#{INTERVAL} N:#{paused.size}"
puts "PUTVAL #{HOSTNAME}/resque_worker/gauge-stuck_parents interval=#{INTERVAL} N:#{stuck_parents.size}"
puts "PUTVAL #{HOSTNAME}/resque_worker/gauge-stuck_children interval=#{INTERVAL} N:#{stuck_children.size}"

counts.each do |target, items|
  puts "PUTVAL #{HOSTNAME}/resque_worker/gauge-#{target}_working interval=#{INTERVAL} N:#{items.size}"
end

times = [1, 5, 15, 30, 60, 120, 180, 540]
ages = children.group_by do |item|
  runtime = Time.now.to_i - item.start_time
  runtime = 0 if item.start_time == 0
  times.find {|t| runtime < (t * 60)}
end

times.each do |t|
  items = ages[t] || []
  puts "PUTVAL #{HOSTNAME}/resque_worker/gauge-runtime_#{t} interval=#{INTERVAL} N:#{items.size}"
end
