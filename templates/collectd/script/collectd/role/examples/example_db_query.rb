query = <<-EOF
  select count(id) from users;
EOF

# pick a non-critical db if possible
source = Rubber.instances.for_role("db").first
source ||= Rubber.instances.for_role("db", "primary" => true).first
db_host = source ? source.full_name : 'localhost'

command = "psql -U#{Rubber.config.db_slave_user}"
command << " -h #{db_host}"
command << " #{Rubber.config.db_name} --tuples-only --no-align"

# execute a sql query to get some data
data = `echo "#{query}" | #{command}`
fail "Couldn't execute command" if $?.exitstatus > 0

# print graph data values
puts "PUTVAL #{HOSTNAME}/users/total interval=#{INTERVAL} N:#{data}"
