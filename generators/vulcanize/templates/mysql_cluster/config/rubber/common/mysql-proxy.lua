<%
  @path = "/etc/mysql/mysql-proxy.lua"
  proxy_cmd = "mysql-proxy --daemon --proxy-lua-script=#{@path}"
  rubber_instances.for_role('mysql_sql').each do |ic|
    proxy_cmd << " --proxy-backend-addresses=#{ic.full_name}:3306"
  end
  @post = <<-SCRIPT
    ! killall mysql-proxy
    #{proxy_cmd}
  SCRIPT
%>

-- we could put a lua script here if we needed to customize mysql-proxy behavior
