<%
  @path = "#{Rubber.root}/config/puma.rb"
%>

environment "production"

# Set the minimum and maximum number of threads that are available in the pool.
# Puma will automatically scale the number of threads based on how much traffic is present. The current default is 0:16. 
threads 8, 32

pidfile "/var/run/puma.pid"

# You should use pume v. 2.0.0.x if you want to daemonize process
daemonize true if respond_to?(:daemonize)

# This is where we specify the socket.
# We will point the upstream Nginx module to this socket later on
bind "unix:///var/run/puma.sock"

# Set the path of the log files inside the log folder of the testapp
stdout_redirect "<%= Rubber.root %>/log/puma.stdout.log", "<%= Rubber.root %>/log/puma.stderr.log", true if respond_to?(:stdout_redirect)