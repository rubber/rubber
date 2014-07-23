namespace :rubber do

  desc <<-DESC
    Sets up the network security groups
    All defined groups will be created, and any not defined will be removed.
    Likewise, rules within a group will get created, and those not will be removed
  DESC
  required_task :setup_security_groups do
    servers = find_servers_for_task(current_task)

    servers.collect(&:host).each{ |host| cloud.setup_security_groups(host) }
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

  desc <<-DESC
    Add security rule to specified security group
  DESC
  required_task :add_security_group_rule_by_id do
    if !ENV['GROUP_ID'] ||  !ENV['FROM_PORT'] || !ENV['TO_PORT'] || !ENV['SOURCE']
      puts "Usage: rubber:add_security_group_rule_by_id GROUP_ID=sg-xxxxx PROTOCOL=tcp FROM_PORT=xx TO_PORT=xx SOURCE=xx.xx.xx.xx/32"
      next
    end
    cloud.add_security_group_rule_by_id(ENV['GROUP_ID'], ENV['PROTOCOL'] || "tcp", ENV['FROM_PORT'], ENV['TO_PORT'], ENV['SOURCE'])
  end

  def get_assigned_security_groups(host=nil, roles=[], vpc_id=nil)
    env = rubber_cfg.environment.bind(roles, host)
    security_groups = env.assigned_security_groups
    if env.auto_security_groups
      security_groups << host
      security_groups += roles
    end

    security_groups = security_groups.uniq.compact.reject {|x| x.empty? }
    security_groups = security_groups.collect {|x| vpc_id ? get_security_group_ids(cloud.isolate_group_name(x), vpc_id).join : cloud.isolate_group_name(x)}.reject {|x| x.empty? }

    return security_groups
  end
end

def get_security_group_ids(group_name=nil,vpc_id=nil)
  cloud.describe_security_groups(group_name,vpc_id).collect{|g| g[:group_id]}
end
