require 'rubber/cloud/aws/base'

module Rubber
  module Cloud

    class Aws::Classic < Aws::Base

      def setup_security_groups(host=nil, roles=[])
        rubber_cfg = Rubber::Configuration.get_configuration(Rubber.env)
        scoped_env = rubber_cfg.environment.bind(roles, host)
        security_group_defns = Hash[scoped_env.security_groups.to_a]

        if scoped_env.auto_security_groups
          sghosts = (scoped_env.rubber_instances.collect{|ic| ic.name } + [host]).uniq.compact
          sgroles = (scoped_env.rubber_instances.all_roles + roles).uniq.compact
          security_group_defns = inject_auto_security_groups(security_group_defns, sghosts, sgroles)
        end

        sync_security_groups(security_group_defns)
      end

      def describe_security_groups(group_name=nil)
        groups = []

        opts = {}
        opts["group-name"] = group_name if group_name
        response = compute_provider.security_groups.all(opts).reject { |group| group.vpc_id }

        response.each do |item|
          group = {}
          group[:name] = item.name
          group[:description] = item.description

          item.ip_permissions.each do |ip_item|
            group[:permissions] ||= []
            rule = {}

            rule[:protocol] = ip_item["ipProtocol"]
            rule[:from_port] = ip_item["fromPort"]
            rule[:to_port] = ip_item["toPort"]

            ip_item["groups"].each do |rule_group|
              rule[:source_groups] ||= []
              source_group = {}
              source_group[:account] = rule_group["userId"]

              # Amazon doesn't appear to be returning the groupName value when running in a default VPC.  It's possible
              # it's only returned for EC2 Classic.  This is distinctly in conflict with the API documents and thus
              # appears to be a bug on Amazon's end.  Nonetheless, we need to handle it because otherwise our security
              # group rule matching logic will fail and it messes up our users.
              #
              # Since every top-level item has both an ID and a name, if we're lacking the groupName we can search
              # through the items for the one matching the groupId we have and then use its name value.  This should
              # represent precisely the same data.
              source_group[:name] = if rule_group["groupName"]
                                      rule_group["groupName"]
                                    elsif rule_group["groupId"]
                                      matching_security_group = response.find { |item| item.group_id == rule_group["groupId"] }
                                      matching_security_group ? matching_security_group.name : nil
                                    else
                                      nil
                                    end

              rule[:source_groups] << source_group
            end if ip_item["groups"]

            ip_item["ipRanges"].each do |ip_range|
              rule[:source_ips] ||= []
              rule[:source_ips] << ip_range["cidrIp"]
            end if ip_item["ipRanges"]

            group[:permissions] << rule
          end

          groups << group
        end

        groups
      end

      private

      def find_security_group_by_name(name)
        compute_provider.security_groups.all('group-name' => name).reject { |group| group.vpc_id }.first
      end

      def create_security_group(group_name, group_description)
        compute_provider.security_groups.create(:name => group_name, :description => group_description)
      end

      def destroy_security_group(group_name)
        find_security_group_by_name(group_name).destroy
      end

      def add_security_group_rule(group_name, protocol, from_port, to_port, source)
        group = find_security_group_by_name(group_name)
        opts = {:ip_protocol => protocol || 'tcp'}

        if source.instance_of? Hash
          opts[:group] = {source[:account] => source[:name]}
        else
          opts[:cidr_ip] = source
        end

        group.authorize_port_range(from_port.to_i..to_port.to_i, opts)
      end

      def remove_security_group_rule(group_name, protocol, from_port, to_port, source)
        group = find_security_group_by_name(group_name)
        opts = {:ip_protocol => protocol || 'tcp'}

        if source.instance_of? Hash
          opts[:group] = {source[:account] => source[:name]}
        else
          opts[:cidr_ip] = source
        end

        group.revoke_port_range(from_port.to_i..to_port.to_i, opts)
      end

      def sync_security_groups(groups)
        return unless groups

        groups = Rubber::Util::stringify(groups)
        groups = isolate_groups(groups)
        group_keys = groups.keys.clone()

        # For each group that does already exist in cloud
        cloud_groups = describe_security_groups
        cloud_groups.each do |cloud_group|
          group_name = cloud_group[:name]

          # skip those groups that don't belong to this project/env
          next if env.isolate_security_groups && group_name !~ /^#{isolate_prefix}/

          if group_keys.delete(group_name)
            # sync rules
            capistrano.logger.debug "Security Group already in cloud, syncing rules: #{group_name}"
            group = groups[group_name]

            # convert the special case default rule into what it actually looks like when
            # we query ec2 so that we can match things up when syncing
            rules = group['rules'].clone
            group['rules'].each do |rule|
              if [2, 3].include?(rule.size) && rule['source_group_name'] && rule['source_group_account']
                rules << rule.merge({'protocol' => 'tcp', 'from_port' => '1', 'to_port' => '65535' })
                rules << rule.merge({'protocol' => 'udp', 'from_port' => '1', 'to_port' => '65535' })
                rules << rule.merge({'protocol' => 'icmp', 'from_port' => '-1', 'to_port' => '-1' })
                rules.delete(rule)
              end
            end

            rule_maps = []

            # first collect the rule maps from the request (group/user pairs are duplicated for tcp/udp/icmp,
            # so we need to do this up frnot and remove duplicates before checking against the local rubber rules)
            cloud_group[:permissions].each do |rule|
              source_groups = rule.delete(:source_groups)
              if source_groups
                source_groups.each do |source_group|
                  rule_map = rule.clone
                  rule_map.delete(:source_ips)
                  rule_map[:source_group_name] = source_group[:name]
                  rule_map[:source_group_account] = source_group[:account]
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
                # rules don't match, remove them from cloud and re-add below
                answer = nil
                msg = "Rule '#{rule_map.inspect}' exists in cloud, but not locally"
                if env.prompt_for_security_group_sync
                  answer = Capistrano::CLI.ui.ask("#{msg}, remove from cloud? [y/N]: ")
                else
                  capistrano.logger.info(msg)
                end

                if answer =~ /^y/
                  rule_map = Rubber::Util::symbolize_keys(rule_map)
                  if rule_map[:source_group_name]
                    remove_security_group_rule(group_name, rule_map[:protocol], rule_map[:from_port], rule_map[:to_port], {:name => rule_map[:source_group_name], :account => rule_map[:source_group_account]})
                  else
                    rule_map[:source_ips].each do |source_ip|
                      remove_security_group_rule(group_name, rule_map[:protocol], rule_map[:from_port], rule_map[:to_port], source_ip)
                    end if rule_map[:source_ips]
                  end
                end
              end
            end

            rules.each do |rule_map|
              # create non-existing rules
              capistrano.logger.debug "Missing rule, creating: #{rule_map.inspect}"
              rule_map = Rubber::Util::symbolize_keys(rule_map)
              if rule_map[:source_group_name]
                add_security_group_rule(group_name, rule_map[:protocol], rule_map[:from_port], rule_map[:to_port], {:name => rule_map[:source_group_name], :account => rule_map[:source_group_account]})
              else
                rule_map[:source_ips].each do |source_ip|
                  add_security_group_rule(group_name, rule_map[:protocol], rule_map[:from_port], rule_map[:to_port], source_ip)
                end if rule_map[:source_ips]
              end
            end
          else
            # delete group
            answer = nil
            msg = "Security group '#{group_name}' exists in cloud but not locally"
            if env.prompt_for_security_group_sync
              answer = Capistrano::CLI.ui.ask("#{msg}, remove from cloud? [y/N]: ")
            else
              capistrano.logger.debug(msg)
            end
            destroy_security_group(group_name) if answer =~ /^y/
          end
        end

        # For each group that didnt already exist in cloud
        group_keys.each do |group_name|
          group = groups[group_name]
          capistrano.logger.debug "Creating new security group: #{group_name}"
          # create each group
          create_security_group(group_name, group['description'])
          # create rules for group
          group['rules'].each do |rule_map|
            capistrano.logger.debug "Creating new rule: #{rule_map.inspect}"
            rule_map = Rubber::Util::symbolize_keys(rule_map)
            if rule_map[:source_group_name]
              add_security_group_rule(group_name, rule_map[:protocol], rule_map[:from_port], rule_map[:to_port], {:name => rule_map[:source_group_name], :account => rule_map[:source_group_account]})
            else
              rule_map[:source_ips].each do |source_ip|
                add_security_group_rule(group_name, rule_map[:protocol], rule_map[:from_port], rule_map[:to_port], source_ip)
              end if rule_map[:source_ips]
            end
          end
        end
      end
    end

  end
end
