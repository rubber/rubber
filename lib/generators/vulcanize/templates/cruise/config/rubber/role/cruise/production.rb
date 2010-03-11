<%
  @path = "#{rubber_env.cruise_dir}/config/environments/production.rb"
  @additive = ["# rubber-cruise-start", "# rubber-cruise-end"]
  @post = "ln -sf #{rubber_env.cruise_dir}/public #{rubber_env.cruise_dir}/public/cruise"
%>

# This is needed so nginx can reverse proxy to cruise server
ActionController::AbstractRequest.relative_url_root = "/cruise"
