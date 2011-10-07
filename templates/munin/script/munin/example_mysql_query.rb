#!/usr/bin/env ruby
#
# Example munin plugin for querying stats out of db
# See munin plugin docs http://munin.projects.linpro.no/wiki/Documentation#Plugins
#
# Scripts added to RUBBER_ROOT/script/munin automatically
# get installed as munin plugins by rubber

# remove this line to enable
exit 0

# load just rubber config without loading rails (you can load rails
# if you want, but may be slow if your app loads a lot of plugins)

require "rubber"
env = ENV["RUBBER_ENV"] ||= "development"
root = File.join(File.dirname(__FILE__), '../..')
Rubber::initialize(root, env)

# Print config info need by munin for generating graphs
if ARGV[0] == "config"
  puts 'graph_title User Count'
  puts 'graph_vlabel Users'
  puts 'graph_category Examples'
  puts 'graph_scale no'
  puts 'tusers.label total users'
  puts 'tusers.type GAUGE'
  puts 'nusers.label user delta'
  puts 'nusers.type COUNTER'
  exit 0
end


query = <<-EOF
  select count(id) from users;
EOF

# pick a non-critical db if possible
source = Rubber.instances.for_role("mysql_util").first
source ||= Rubber.instances.for_role("mysql_slave").first
source ||= Rubber.instances.for_role("mysql_master").first
db_host = source ? source.full_name : 'localhost'

command = "mysql -u #{Rubber.config.db_slave_user}"
command << " --password=#{Rubber.config.db_pass}"
command << " -h #{db_host}"
command << " #{Rubber.config.db_name} --skip-column-names"

# execute a sql query to get some data
data = `echo "#{query}" | #{command}`
fail "Couldn't execute command" if $?.exitstatus > 0

# print graph data values
puts "tusers.value #{data}"
puts "nusers.value #{data}"
