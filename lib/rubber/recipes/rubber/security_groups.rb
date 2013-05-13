namespace :rubber do

  desc <<-DESC
    Sets up the network security groups
    All defined groups will be created, and any not defined will be removed.
    Likewise, rules within a group will get created, and those not will be removed
  DESC
  required_task :setup_security_groups do
    servers = find_servers_for_task(current_task)

    cloud.setup_security_groups(servers.collect(&:host))
  end

  desc <<-DESC
    Describes the network security groups
  DESC
  required_task :describe_security_groups do
    groups = cloud.describe_security_groups()
    groups.each do |group|
      puts "#{group[:name]}, #{group[:description]}"
      group[:permissions].each do |perm|
        puts "  protocol: #{perm[:protocol]}"
        puts "  from_port: #{perm[:from_port]}"
        puts "  to_port: #{perm[:to_port]}"
        puts "  source_groups: #{perm[:source_groups].collect {|g| g[:name]}.join(", ") }" if perm[:source_groups]
        puts "  source_ips: #{perm[:source_ips].join(", ") }" if perm[:source_ips]
        puts "\n"
      end if group[:permissions]
      puts "\n"
    end
  end


  def get_assigned_security_groups(host=nil, roles=[])
    env = rubber_cfg.environment.bind(roles, host)
    security_groups = env.assigned_security_groups
    if env.auto_security_groups
      security_groups << host
      security_groups += roles
    end
    security_groups = security_groups.uniq.compact.reject {|x| x.empty? }
    security_groups = security_groups.collect {|x| cloud.isolate_group_name(x) }
    return security_groups
  end
end