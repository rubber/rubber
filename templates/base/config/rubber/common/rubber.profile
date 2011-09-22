<%
  @path = "/etc/profile.d/rubber.sh"
  current_path = "/mnt/#{rubber_env.app_name}-#{RUBBER_ENV}/current" 
%>

# convenience to simply running rails console, etc with correct env
export RUBBER_ENV=<%= RUBBER_ENV %>
export RAILS_ENV=<%= RUBBER_ENV %>
alias current="cd <%= current_path %>"
alias release="cd <%= RUBBER_ROOT %>"

# Always use rubygems
export RUBYOPT="rubygems"
