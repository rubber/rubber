namespace :rubber do

  desc <<-DESC
    Sets up the network security groups
    All defined groups will be created, and any not defined will be removed.
    Likewise, rules within a group will get created, and those not will be removed
  DESC
  required_task :setup_security_groups do
    env = rubber_cfg.environment.bind()
    security_group_defns = env.security_groups
    if env.auto_security_groups
      hosts = rubber_cfg.instance.collect{|ic| ic.name }
      roles = rubber_cfg.instance.all_roles
      security_group_defns = inject_auto_security_groups(security_group_defns, hosts, roles)
      sync_security_groups(security_group_defns)
    else
      sync_security_groups(security_group_defns)
    end
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


  def inject_auto_security_groups(groups, hosts, roles)
    hosts.each do |name|
      group_name = name
      groups[group_name] ||= {'description' => "Rubber automatic security group for host: #{name}", 'rules' => []}
    end
    roles.each do |name|
      group_name = name
      groups[group_name] ||= {'description' => "Rubber automatic security group for role: #{name}", 'rules' => []}
    end
    return groups
  end

  def sync_security_groups(groups)
    env = rubber_cfg.environment.bind()
    return unless groups

    groups = Rubber::Util::stringify(groups)
    group_keys = groups.keys.clone()

    # For each group that does already exist in ec2
    cloud_groups = cloud.describe_security_groups()
    cloud_groups.each do |cloud_group|
      group_name = cloud_group[:name]
      if group_keys.delete(group_name)
        # sync rules
        logger.debug "Security Group already in ec2, syncing rules: #{group_name}"
        group = groups[group_name]
        rules = group['rules'].clone
        rule_maps = []

        # first collect the rule maps from the request (group/user pairs are duplicated for tcp/udp/icmp,
        # so we need to do this up frnot and remove duplicates before checking against the local rubber rules)
        cloud_group[:permissions].each do |rule|
          if rule[:source_groups]
            rule.source_groups.each do |source_group|
              rule_map = {:source_group_name => source_group[:name], :source_group_account => source_group[:account]}
              rule_map = Rubber::Util::stringify(rule_map)
              rule_maps << rule_map unless rule_maps.include?(rule_map)
            end
          else
            rule_map = Rubber::Util::stringify(rule)
            rule_maps << rule_map unless rule_maps.include?(rule_map)
          end
        end if cloud_group[:permissions]
        # For each rule, if it exists, do nothing, otherwise remove it as its no longer defined locally
        rule_maps.each do |rule_map|
          if rules.delete(rule_map)
            # rules match, don't need to do anything
            # logger.debug "Rule in sync: #{rule_map.inspect}"
          else
            # rules don't match, remove them from ec2 and re-add below
            answer = Capistrano::CLI.ui.ask("Rule '#{rule_map.inspect}' exists in ec2, but not locally, remove from ec2? [y/N]?: ")
            rule_map = Rubber::Util::symbolize_keys(rule_map)
            if rule_map[:source_group_name]
              cloud.remove_security_group_rule(group_name, nil, nil, nil, {:name => rule_map[:source_group_name], :account => rule_map[:source_group_account]})
            else
              rule_map[:source_ips].each do |source_ip|
                cloud.remove_security_group_rule(group_name, rule_map[:protocol], rule_map[:from_port], rule_map[:to_port], source_ip)
              end if rule_map[:source_ips] && answer =~ /^y/
            end
          end
        end

        rules.each do |rule_map|
          # create non-existing rules
          logger.debug "Missing rule, creating: #{rule_map.inspect}"
          rule_map = Rubber::Util::symbolize_keys(rule_map)
          if rule_map[:source_group_name]
            cloud.add_security_group_rule(group_name, nil, nil, nil, {:name => rule_map[:source_group_name], :account => rule_map[:source_group_account]})
          else
            rule_map[:source_ips].each do |source_ip|
              cloud.add_security_group_rule(group_name, rule_map[:protocol], rule_map[:from_port], rule_map[:to_port], source_ip)
            end if rule_map[:source_ips]
          end
        end
      else
        # when using auto groups, get prompted too much to delete when
        # switching between production/staging since the hosts aren't shared
        # between the two environments
        if env.force_security_group_cleanup || ! env.auto_security_groups
          # delete group
          answer = Capistrano::CLI.ui.ask("Security group '#{group_name}' exists in ec2 but not locally, remove from ec2? [y/N]: ")
          cloud.destroy_security_group(group_name) if answer =~ /^y/
        end
      end
    end

    # For each group that didnt already exist in ec2
    group_keys.each do |group_name|
      group = groups[group_name]
      logger.debug "Creating new security group: #{group_name}"
      # create each group
      cloud.create_security_group(group_name, group['description'])
      # create rules for group
      group['rules'].each do |rule_map|
        logger.debug "Creating new rule: #{rule_map.inspect}"
        rule_map = Rubber::Util::symbolize_keys(rule_map)
        if rule_map[:source_group_name]
          cloud.add_security_group_rule(group_name, nil, nil, nil, {:name => rule_map[:source_group_name], :account => rule_map[:source_group_account]})
        else
          rule_map[:source_ips].each do |source_ip|
            cloud.add_security_group_rule(group_name, rule_map[:protocol], rule_map[:from_port], rule_map[:to_port], source_ip)
          end if rule_map[:source_ips]
        end
      end
    end
  end

end