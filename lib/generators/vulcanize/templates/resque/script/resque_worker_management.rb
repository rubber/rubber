#!/usr/bin/env ruby

STDOUT.sync = true
STDERR.sync = true

def load_env(rubber_only=true)
  env = ENV["RUBBER_ENV"] ||= "development"
  root = File.expand_path('../..', __FILE__)
  rails_env_file = File.join(root, 'config', 'environment.rb')

  if ! rubber_only && File.exists?(rails_env_file)
    require(rails_env_file)
  else
    require "bundler/setup" if File.exist?(File.join(root, "Gemfile"))
    require "rubber"
    Rubber::initialize(root, env)
  end
end


def start_all(workers)
  puts "Starting all workers"
  # fork then load rails env so script runs quick, yet we don't overload
  # machine by loading env for each worker
  daemonize(log_file('all')) do
    load_env(false)
    puts "Preloaded environment for all workers"

    workers.each_with_index do |worker, i|
      start(worker, i)
    end
  end
end

def start(worker, index)
  puts "Starting worker #{index}/#{worker.queues}"

  log_file = log_file(index)
  pid_file = pid_file(index)

  queues = worker.queues.to_s.split(',')

  daemonize(log_file, pid_file) do
    # load env for each worker, if starting multiple, this will be a no-op due
    # to start_all preloading the env
    load_env(false)
    resque_worker = Resque::Worker.new(*queues)
    resque_worker.verbose = ENV['LOGGING'] || ENV['VERBOSE']
    resque_worker.very_verbose = ENV['VVERBOSE']

    puts "*** Starting worker #{resque_worker}"
    resque_worker.work(worker.poll_interval.to_i || 5) # interval, will block
  end

end

def stop_all(workers, signal)
  puts "Stopping all workers"
  workers.size.times do |i|
    stop(i, signal)
  end
end

# Resque workers respond to a few different signals:
#
# QUIT - Wait for child to finish processing then exit
# TERM / INT - Immediately kill child then exit
# USR1 - Immediately kill child but don't exit
# USR2 - Don't start to process any new jobs
# CONT - Start to process new jobs again after a USR2
def stop(index, signal)
  puts "Stopping worker #{index}"

  pid_file = pid_file(index)
  pid = File.read(pid_file).to_i rescue nil
  if pid
    puts "Killing worker #{index}: pid #{pid} - #{signal}"
    begin
      Process.kill(signal, pid)
    rescue Exception => e
      puts e
    end
    File.delete(pid_file) if File.exist?(pid_file)
  else
    puts "No pid file for worker #{index}: #{pid_file}"
  end
end

def daemonize(log_file, pid_file=nil)
  return if fork
  Process::setsid
  exit!(0) if fork
  Dir::chdir(Rubber.root)
  File.umask 0000
  FileUtils.touch log_file
  STDIN.reopen    log_file
  STDOUT.reopen   log_file, "a"
  STDERR.reopen   log_file, "a"
  STDOUT.sync = true
  STDERR.sync = true

  File.open(pid_file, 'w') {|f| f.write("#{Process.pid}") } if pid_file

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
signal = ARGV[2] || "QUIT"
if action.nil? || ! %w[start stop restart].include?(action)
  puts "Usage: script/resque_worker_management.rb [start|stop|restart]"
end

# load just the rubber env so things run quickly
load_env(true)
workers = Rubber.config.resque_workers

case action
  when 'start'
    worker_index ? start(workers[worker_index], worker_index) : start_all(workers)
    # sleep a bit to allow daemonization to complete
    sleep 0.5
  when 'stop'
    worker_index ? stop(worker_index, signal) : stop_all(workers, signal)
  when 'restart'
    if worker_index
      stop(worker_index, signal)
      start(workers[worker_index], worker_index)
    else
      stop_all(workers, signal)
      start_all(workers)
    end
    # sleep a bit to allow daemonization to complete
    sleep 0.5
end
