#!/usr/bin/env ruby
#
# Example munin plugin.
# See munin plugin docs http://munin.projects.linpro.no/wiki/Documentation#Plugins
#
# Scripts added to RUBBER_ROOT/script/munin automatically
# get installed as munin plugins by rubber

# remove this line to enable
exit 0

# Print config info need by munin for generating graphs
if ARGV[0] == "config"
  puts 'graph_title Example Stats'
  puts 'graph_vlabel random 1-100'
  puts 'graph_category Examples'
  puts 'graph_scale no'
  puts 'rand.label random'

  exit 0
end

# print graph data values
puts "rand.value #{rand(100)}"
