<%
  current_path = "/mnt/#{rubber_env.app_name}-#{Rubber.env}/current"
  cwd_path = "#{current_path}/#{rubber_env.nodejs.app_dir}"
  @path = "#{cwd_path}/#{rubber_env.nodejs.config_file}"
%>

config = {
  // my config goes here
};

module.exports = config
