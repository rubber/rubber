<%
  @path = "#{rubber_env.selenium_grid_hub_dir}/startup.sh"
  @perms = 0755

  args = []
  args << '-Xms256m'
  args << "-Xmx#{rubber_env.selenium_grid_hub_max_heap_in_mb}m"
  args << "-XX:MaxPermSize=#{rubber_env.selenium_grid_hub_permgen_in_mb}m"
  args << '-server'
  args << '-Xdebug'
  args << '-Xrunjdwp:transport=dt_socket,server=y,suspend=n,address=5005'
  args << "-cp #{rubber_env.selenium_grid_hub_dir}/selenium-server-standalone-#{rubber_env.selenium_grid_hub_version}.jar:#{rubber_env.selenium_grid_hub_dir}/json-simple.jar:#{rubber_env.selenium_grid_hub_dir}/gelfj.jar"
  args << "-Djava.util.logging.config.file=#{rubber_env.selenium_grid_hub_dir}/logging.properties"
  args << "org.openqa.grid.selenium.GridLauncher"
  args << "-role hub"
  args << "-throwOnCapabilityNotPresent false"
  args << "-browserTimeout 60"
  args << "-log #{rubber_env.selenium_grid_hub_log_dir}/hub.log"
%>
#!/bin/bash

ulimit -n 65536
nohup java <%= args.join(' ') %> >> <%= rubber_env.selenium_grid_hub_log_dir %>/hub.log 2>&1 & echo $! > <%= rubber_env.selenium_grid_hub_dir %>/hub.pid