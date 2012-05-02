#!/usr/bin/env ruby

STDOUT.sync = STDERR.sync = true

action = ARGV[0]
run_script = ARGV[1]

if ARGV.size > 2 || (action == 'run' && run_script.nil?)
  puts "usage: #{File.basename(__FILE__)} [config | run script]"
  puts "\tWith no arguments run all scripts in plugin dir in an infinite loop"
  puts "\tWith config action, lists scripts that would be run"
  puts "\tWith run action, runs the given script"
  exit 1
end

HOSTNAME = ENV["COLLECTD_HOSTNAME"] || `hostname -f`.chomp
INTERVAL = (ENV["COLLECTD_INTERVAL"] || 60).to_i

env = ENV["RUBBER_ENV"] ||= "development"
root = File.expand_path(File.dirname(__FILE__) + '/../..')

STDERR.reopen("#{root}/log/collectd-runner.log", "a") unless action == 'run'

require "rubber"
Rubber::initialize(root, env)

# Gives us a way to run a single script
if action == 'run'
  load ARGV[1]
  exit
end

# for each script in our source tree, call that script to generate collectd data
#
# scripts directly in script_dir get run for each host
# scripts in script_dir/role/role_name only get run if current host is a member of that role
# scripts in script_dir/host/host_name only get run if current host is that host_name

scripts = []
this_script = File.expand_path(__FILE__)
script_dir = "#{Rubber.root}/script/collectd"

Dir["#{script_dir}/**/*"].each do |script|
  next if File.directory?(script)
  next if script == this_script

  # skip scripts not specific to the current host or roles
  #
  relative = script.gsub("#{script_dir}/", "")
  segments = relative.split("/")
  if segments[0] == 'host'
    next unless segments[1] == Rubber.config.host
  end
  if segments[0] == 'role'
    next unless Array(Rubber.config.roles).include?(segments[1])
  end

  scripts << script
end

# Allows collectd conf to see if it needs to setup an Exec Plugin block
if ARGV[0] == 'config'
  puts scripts.join("\n")
  exit
end

# Collectd scripts can run indefinately, outputting values
# every INTERVAL.  We do this for all the rubber/collectd
# scripts so that we keep the ruby vm loaded for faster
# execution time at the expense of  the ruby vm memory usage.
#
# Foreach rubber/collectd plugin script, load it in a fork
# to run so that our master loop doesn't get compromised by
# a bad script, segfault, etc.
#
STDERR.puts "#{Time.now}: Starting rubber-collectd execution loop"
loop do
  start_time = Time.now.to_i

  scripts.each do |script|
    fork do
      begin
        load script
      rescue Exception => e
        STDERR.puts("#{script}: #{e}")
      end
    end
  end
  Process.waitall

  run_time = Time.now.to_i - start_time
  begin
    puts "PUTVAL #{HOSTNAME}/rubber/gauge-collectd_runner interval=#{INTERVAL} N:#{run_time}"
  rescue Errno::EPIPE
    STDERR.puts "#{Time.now}: Exiting rubber-collectd execution loop"
    exit
  end

  sleep_time = INTERVAL - run_time
  if sleep_time < 0
    sleep_time = INTERVAL
    STDERR.puts("Plugins taking longer (#{run_time}s) than #{INTERVAL}s")
  end

  sleep sleep_time
  
end
