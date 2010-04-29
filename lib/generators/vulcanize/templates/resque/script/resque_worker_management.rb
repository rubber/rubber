#!/usr/bin/env ruby

env = ENV["RUBBER_ENV"] ||= "development"
root = File.join(File.dirname(__FILE__), '..')
rails_env_file = File.join(root, 'config', 'environment.rb')

if File.exists? rails_env_file
  require(rails_env_file)
else
  require "rubber"
  Rubber::initialize(root, env)
  require 'resque'
  require "#{root}/config/initializers/resque.rb"
end

def start_all(workers)
  puts "Starting all workers"
  workers.each_with_index do |worker, i|
    start(worker, i)
  end
end

def start(worker, index)
  puts "Starting worker #{index}/#{worker.queues}"

  log_file = log_file(index)
  pid_file = pid_file(index)

  queues = worker.queues.to_s.split(',')

  daemonize(log_file, pid_file) do
    resque_worker = Resque::Worker.new(*queues)
    resque_worker.verbose = ENV['LOGGING'] || ENV['VERBOSE']
    resque_worker.very_verbose = ENV['VVERBOSE']

    puts "*** Starting worker #{resque_worker}"
    resque_worker.work(worker.poll_interval.to_i || 5) # interval, will block
  end
end

def stop_all(workers)
  puts "Stopping all workers"
  workers.size.times do |i|
    stop(i)
  end
end

def stop(index)
  puts "Stopping worker #{index}"
  
  pid_file = pid_file(index)
  pid = File.read(pid_file).to_i rescue nil
  if pid
    puts "Killing worker #{index}: pid #{pid}"
    begin
      Process.kill("QUIT", pid)
    rescue Exception => e
      puts e
    end
    File.delete(pid_file) if File.exist?(pid_file)
  else
    puts "No pid file for worker #{index}: #{pid_file}"
  end
end

def daemonize(log_file, pid_file)
  return if fork
  Process::setsid
  exit!(0) if fork
  Dir::chdir("/")
  File.umask 0000
  FileUtils.touch log_file
  STDIN.reopen    log_file
  STDOUT.reopen   log_file, "a"
  STDERR.reopen   log_file, "a"

  File.open(pid_file, 'w') {|f| f.write("#{Process.pid}") }
  
  yield if block_given?
  exit(0)
end

def pid_file(index)
  File.expand_path "#{Rubber.root}/tmp/pids/resque_worker_#{index}.pid"
end

def log_file(index)
  File.expand_path "#{Rubber.root}/log/resque_worker_#{index}.log"
end

action = ARGV[0]
worker_index = ARGV[1] ? ARGV[1].to_i : nil
if action.nil? || ! %w[start stop restart].include?(action)
  puts "Usage: script/resque_worker_management.rb [start|stop|restart]"
end

workers = Rubber.config.resque_workers

case action
  when 'start'
    worker_index ? start(workers[worker_index], worker_index) : start_all(workers)
  when 'stop'
    worker_index ? stop(worker_index) : stop_all(workers)
  when 'restart'
    if worker_index
      stop(worker_index)
      start(workers[worker_index], worker_index)
    else
      stop_all(workers)
      start_all(workers)
    end
end
