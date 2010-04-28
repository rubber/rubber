#!/usr/bin/env ruby

def start_all(workers)
  workers.each_with_index do |worker, i|
    start(worker, i)
  end
end

def start(worker, index)
  cmd = "cd #{Rails.root}; RAILS_ENV=#{Rails.env} INTERVAL=1 QUEUES=#{worker.queues} nohup rake resque:work &> log/resque_worker_default_#{index}.log & echo $! > tmp/pids/resque_worker_default_#{index}.pid"
  `#{cmd}`
end

def stop_all(workers)
  workers.size.times do |i|
    stop(i)
  end

  sleep 11 #wait for process to finish
end

def stop(index)
  cmd = "cd #{Rails.root} && kill `cat tmp/pids/resque_worker_default_#{index}.pid` && rm -f tmp/pids/resque_worker_default_#{index}.pid; exit 0;"
  `#{cmd}`
end




action = ARGV[0]
worker_index = ARGV[1].present? ? ARGV[1].to_i : nil
if action.blank? || ! %w[start stop restart].include?(action)
  puts "Usage: script/runner script/resque_worker_management.rb [start|stop|restart]"
end

workers = RUBBER_CONFIG.resque_workers

case action
  when 'start'
    worker_index.blank? ? start_all(workers) : start(workers[worker_index], worker_index)
  when 'stop'
    worker_index.blank? ? stop_all(workers) : stop(worker_index)
  when 'restart'
    if worker_index.blank?
      stop_all(workers)
      start_all(workers)
    else
      stop(worker_index)
      start(workers[worker_index], worker_index)
    end
end
