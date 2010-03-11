<%
  @path = "/etc/profile.d/rubber.sh"
%>

# convenience to simply running rails console, etc with correct env
export RUBBER_ENV=<%= RUBBER_ENV %>
export RAILS_ENV=<%= RUBBER_ENV %>
alias current="cd <%= RUBBER_ROOT %>"

# make sure we use the right ruby since REE installs into /usr/local
export PATH=<%= rubber_env.ruby_prefix %>/bin:$PATH

# Always use rubygems
export RUBYOPT="rubygems"
