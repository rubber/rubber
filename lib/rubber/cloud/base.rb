module Rubber
  module Cloud

    class Base

      attr_reader :env, :capistrano

      def initialize(env, capistrano)
        @env = env
        @capistrano = capistrano
      end

      def before_create_instance(instance_alias, role_names)
        # No-op by default.
      end

      def after_create_instance(instance)
        # No-op by default.
      end

      def before_refresh_instance(instance)
        # No-op by default.
      end

      def after_refresh_instance(instance)
        setup_security_groups(instance.name, instance.role_names)
      end

      def before_stop_instance(instance)
        # No-op by default.
      end

      def after_stop_instance(instance)
        # No-op by default.
      end

      def before_start_instance(instance)
        # No-op by default.
      end

      def after_start_instance(instance)
        # No-op by default.
      end

      def isolate_prefix
        "#{env.app_name}_#{Rubber.env}_"
      end

      def active_state
        raise NotImplementedError, "active_state not implemented in base adapter"
      end

      def isolate_group_name(group_name)
        if env.isolate_security_groups
          group_name =~ /^#{isolate_prefix}/ ? group_name : "#{isolate_prefix}#{group_name}"
        else
          group_name
        end
      end

      def isolate_groups(groups)
        renamed = {}

        groups.each do |name, group|
          new_name = isolate_group_name(name)
          new_group =  Marshal.load(Marshal.dump(group))

          new_group['rules'].each do |rule|
            old_ref_name = rule['source_group_name']
            if old_ref_name
              # don't mangle names if the user specifies this is an external group they are giving access to.
              # remove the external_group key to allow this to match with groups retrieved from cloud
              is_external = rule.delete('external_group')
              if ! is_external && old_ref_name !~ /^#{isolate_prefix}/
                rule['source_group_name'] = isolate_group_name(old_ref_name)
              end
            end
          end

          renamed[new_name] = new_group
        end

        renamed
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

        groups
      end

      def setup_security_groups(host=nil, roles=[])
        raise "Digital Ocean provider can only set up one host a time" if host.split(',').size != 1

        rubber_cfg = Rubber::Configuration.get_configuration(Rubber.env)
        scoped_env = rubber_cfg.environment.bind(roles, host)
        security_group_defns = Hash[scoped_env.security_groups.to_a]


        if scoped_env.auto_security_groups
          sghosts = (scoped_env.rubber_instances.collect{|ic| ic.name } + [host]).uniq.compact
          sgroles = (scoped_env.rubber_instances.all_roles + roles).uniq.compact
          security_group_defns = inject_auto_security_groups(security_group_defns, sghosts, sgroles)
        end

        groups = Rubber::Util::stringify(security_group_defns)
        groups = isolate_groups(groups)

        script = <<-ENDSCRIPT
          # Clear out all firewall rules to start.
          iptables -F

          iptables -I INPUT 1 -i lo -j ACCEPT -m comment --comment 'Enable connections on loopback devices.'
          iptables -I INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT -m comment --comment 'Always allow established connections to remain connected.'
        ENDSCRIPT

        instance = scoped_env.rubber_instances[host]
        instance.security_groups.each do |group_name|
          group = groups[group_name]

          group['rules'].each do |rule|
            protocol = rule['protocol']
            from_port = rule.has_key?('from_port') ? rule['from_port'].to_i : nil
            to_port = rule.has_key?('to_port') ? rule['to_port'].to_i : nil
            source_ips = rule['source_ips']

            if protocol && from_port && to_port && source_ips
              source_ips.each do |source|
                if from_port != to_port
                  script << "\niptables -A INPUT -p #{protocol} --dport #{from_port}:#{to_port} --source #{source} -j ACCEPT -m comment --comment '#{group_name}'"
                else
                  script << "\niptables -A INPUT -p #{protocol} --dport #{to_port} --source #{source} -j ACCEPT -m comment --comment '#{group_name}'"
                end
              end
            end
          end
        end

        script << "\niptables -A INPUT -j DROP -m comment --comment 'Disable all other connections.'"

        capistrano.run_script 'setup_firewall_rules', script, :hosts => instance.external_ip
      end

      def describe_security_groups(group_name=nil)
        rules = capistrano.capture("iptables -S INPUT", :hosts => rubber_env.rubber_instances.collect(&:external_ip)).strip.split("\r\n")
        scoped_rules = rules.select { |r| r =~ /dport/ }

        groups = []

        scoped_rules.each do |rule|
          group = {}
          discovered_rule = {}

          parts = rule.split(' ').each_slice(2).to_a
          parts.each do |arg, value|
            case arg
              when '-p' then discovered_rule[:protocol] = value
              when '--dport' then discovered_rule[:from_port] = value; discovered_rule[:to_port] = value
              when '--comment' then group[:name] = value
            end
          end

          # Consolidate rules for groups with the same name.
          existing_group = groups.find { |g| g[:name] == group[:name]}
          if existing_group
            existing_group[:permissions] << discovered_rule
          else
            group[:permissions] = [discovered_rule]
            groups << group
          end
        end

        groups
      end

    end

  end
end