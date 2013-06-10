<%
  @path = "#{rubber_env.browsermob_proxy_dir}/startup.sh"
  @perms = 0755

  proxy_server = rubber_instances.for_role("caching_proxy").first

  args = []
  args << '-Xms256m'
  args << "-Xmx#{rubber_env.browsermob_proxy_max_heap_in_mb}m"
  args << "-XX:MaxPermSize=#{rubber_env.browsermob_proxy_permgen_in_mb}m"
  args << '-Djsse.enableSNIExtension=false'

  if proxy_server
    args << "-Dhttp.proxyHost=#{proxy_server.internal_ip}"
    args << "-Dhttp.proxyPort=#{rubber_env.caching_proxy_port}"
  end
%>
#!/bin/bash

ulimit -n 65536
JAVA_OPTS="<%= args.join(' ') %>" nohup <%= rubber_env.browsermob_proxy_dir %>/bin/browsermob-proxy --port <%= rubber_env.browsermob_proxy_port %> >> <%= rubber_env.browsermob_proxy_log_dir %>/browsermob_proxy.log 2>&1 & echo $! > <%= rubber_env.browsermob_proxy_dir %>/browsermob_proxy.pid
