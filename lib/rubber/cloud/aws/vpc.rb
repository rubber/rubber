require 'rubber/cloud/aws/base'

module Rubber
  module Cloud
  
    class Aws::Vpc < Aws::Base

      def before_create_instance(instance_alias, role_names, availability_zone, is_public)
        setup_vpc(availability_zone, is_public)
        setup_security_groups(instance_alias, role_names)
      end

      def setup_security_groups(host=nil, roles=[])
        rubber_cfg = Rubber::Configuration.get_configuration(Rubber.env)
        scoped_env = rubber_cfg.environment.bind(roles, host)
        security_group_defns = Hash[scoped_env.security_groups.to_a]

        if scoped_env.auto_security_groups
          sghosts = (scoped_env.rubber_instances.collect{|ic| ic.name } + [host]).uniq.compact
          sgroles = (scoped_env.rubber_instances.all_roles + roles).uniq.compact
          security_group_defns = inject_auto_security_groups(security_group_defns, sghosts, sgroles)
        end

        sync_security_groups(scoped_env.rubber_instances.artifacts['vpc']['id'], security_group_defns)
      end

      # Idempotent call which will ensure we have a vpc configured as well as a
      # subnet for the given availability zone
      def setup_vpc(availability_zone, is_public)
        bound_env = load_bound_env

        vpc_id = get_vpc_id(bound_env)
        vpc_cfg = bound_env.cloud_providers.aws.vpc

        unless vpc_id
          vpc = create_vpc "#{bound_env.app_name} #{Rubber.env}", vpc_cfg.vpc_subnet

          add_vpc_to_instance_file bound_env, vpc

          capistrano.logger.debug "Created VPC #{vpc.id}"

          vpc_id = vpc.id
        end

        public_private = is_public ? "public" : "private"

        cidr = vpc_cfg.instance_subnets[availability_zone][public_private]

        subnet = subnet_for_availability_zone bound_env, availability_zone, is_public

        unless subnet
          unless is_public
            capistrano.logger.info ":ssh_gateway required in deploy.rb to communicate with instances in a private network"
          end

          subnet_name = "#{bound_env.app_name} #{Rubber.env} #{availability_zone} #{public_private}"
          subnet = create_vpc_subnet vpc_id, subnet_name, availability_zone, cidr, is_public

          capistrano.logger.debug "Created #{public_private} subnet #{subnet.subnet_id} #{availability_zone} #{cidr}"

          add_subnet_to_instance_file bound_env, subnet, is_public
        end
      end

      def destroy_vpc(vpc_id)
        compute_provider.vpcs.destroy(vpc_id)
      end

      def describe_security_groups(vpc_id, group_name=nil)
        groups = []

        # As of 10/2/2015, vpcId isn't a valid filter, so we have to filter
        # manually
        opts = {}
        opts["group-name"] = group_name if group_name
        response = compute_provider.security_groups.all(opts)

        response.each do |item|
          next if item.vpc_id != vpc_id
          group = {}
          group[:group_id] = item.group_id
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

              source_group[:group_id] = rule_group["groupId"]

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

      def create_volume(instance, volume_spec)
        fog_options = Rubber::Util.symbolize_keys(volume_spec['fog_options'] || {})
        volume_data = {
            :size => volume_spec['size'], :availability_zone => volume_spec['zone']
        }.merge(fog_options)
        volume = compute_provider.volumes.create(volume_data)
        volume.id
      end

      def after_create_volume(instance, volume_id, volume_spec)
        # After we create an EBS volume, we need to attach it to the instance.
        volume = compute_provider.volumes.get(volume_id)
        server = compute_provider.servers.get(instance.instance_id)
        volume.device = volume_spec['device']
        volume.server = server
      end

      def before_destroy_volume(volume_id)
        # Before we can destroy an EBS volume, we must detach it from any running instances.
        volume = compute_provider.volumes.get(volume_id)
        volume.force_detach
      end

      def destroy_volume(volume_id)
        compute_provider.volumes.get(volume_id).destroy
      end

      def describe_volumes(volume_id=nil)
        volumes = []
        opts = {}
        opts[:'volume-id'] = volume_id if volume_id
        response = compute_provider.volumes.all(opts)

        response.each do |item|
          volume = {}
          volume[:id] = item.id
          volume[:status] = item.state

          if item.server_id
            volume[:attachment_instance_id] = item.server_id
            volume[:attachment_status] = item.attached_at ? "attached" : "waiting"
          end

          volumes << volume
        end

        volumes
      end

      # resource_id is any Amazon resource ID (e.g., instance ID or volume ID)
      # tags is a hash of tag_name => tag_value pairs
      def create_tags(resource_id, tags)
        # Tags need to be created individually in fog
        tags.each do |k, v|
          compute_provider.tags.create(:resource_id => resource_id,
                                        :key => k.to_s, :value => v.to_s)
        end
      end

      private

      def create_vpc(name, subnet_str)
        vpc = compute_provider.vpcs.create(:cidr_block => subnet_str)

        Rubber::Util.retry_on_failure(StandardError, :retry_sleep => 1, :retry_count => 120) do
          create_tags(vpc.id, :Name => name, :Environment => Rubber.env)
        end

        vpc
      end

      def create_vpc_subnet(vpc_id, name, availability_zone, cidr_block, is_public=false)
        opts = {
          :vpc_id => vpc_id,
          :cidr_block => cidr_block,
          :availability_zone => availability_zone
        }

        nat = nil

        if is_public
          opts[:map_public_ip_on_launch] = true
        else
          bound_env = load_bound_env

          # Check for nat in this availability zone
          nat = bound_env.rubber_instances.find do |i|
            i.roles.map(&:name).include?("nat_gateway") &&
              (i.zone == availability_zone)
          end

          unless nat
            fatal("Cannot create a private subnet in #{availability_zone} without a nat_gateway configured in the public subnet", 0)
          end
        end

        subnet = compute_provider.subnets.create opts

        Rubber::Util.retry_on_failure(StandardError, :retry_sleep => 1, :retry_count => 120) do
          create_tags(subnet.subnet_id, :Name => name, :Environment => Rubber.env)
        end

        route_tables = compute_provider.route_tables.all.select do |t|
          t.vpc_id == vpc_id
        end

        subnet_count = compute_provider.subnets.all.count

        # The first subnet comes with a route table.  We will have to create our
        # own route tables for subsequent subnets
        if subnet_count == route_tables.count
          route_table = route_tables.first
        else
          route_table = compute_provider.create_route_table vpc_id

          #cloud_provider.create_route(route_table.id, cidr_block, nil, nil, "local")
        end

        Rubber::Util.retry_on_failure(StandardError, :retry_sleep => 1, :retry_count => 120) do
          create_tags(route_table.id, :Name => name, :Environment => Rubber.env)
        end

        compute_provider.associate_route_table(route_table.id, subnet.subnet_id)

        if is_public
          internet_gateway = create_vpc_internet_gateway(vpc_id)

          # Add a route so that non-local traffic can reach the internet
          compute_provider.create_route(route_table.id, "0.0.0.0/0", internet_gateway.id)
        else
          compute_provider.create_route(route_table.id, "0.0.0.0/0", nil, nat.instance_id)
        end

        subnet
      end

      def create_vpc_internet_gateway(vpc_id)
        gateway = compute_provider.internet_gateways.create
        gateway.attach(vpc_id)
        gateway
      end

      def destroy_subnet(subnet_id)
        compute_provider.subnets.destroy(subnet_id)
      end

      def create_security_group(vpc_id, group_name, group_description)
        compute_provider.security_groups.create :vpc_id => vpc_id,
                                                :name => group_name,
                                                :description => group_description
      end

      def destroy_security_group(group_id)
        compute_provider.security_groups.get(group_id).destroy
      end

      def add_security_group_rule(group_id, protocol, from_port, to_port, source)
        group = compute_provider.security_groups.all('group-id' => group_id).first
        opts = {:ip_protocol => protocol || 'tcp'}

        if source.instance_of? Hash
          opts[:group] = {source[:account] => source[:name]}
        else
          opts[:cidr_ip] = source
        end

        # VPC Security Rules sometimes have nil to/from ports which means the
        # entire range is authorized
        from_port = 0 if from_port.nil?
        from_port = 65535 if to_port.nil?

        group.authorize_port_range(from_port.to_i..to_port.to_i, opts)
      end

      def remove_security_group_rule(group_id, protocol, from_port, to_port, source)
        group = compute_provider.security_groups.get(group_id)
        opts = {:ip_protocol => protocol || 'tcp'}

        if source.instance_of? Hash
          opts[:group] = {source[:account] => source[:name]}
        else
          opts[:cidr_ip] = source
        end

        group.revoke_port_range(from_port.to_i..to_port.to_i, opts)
      end

      def sync_security_groups(vpc_id, groups)
        return unless groups

        groups = Rubber::Util::stringify(groups)
        groups = isolate_groups(groups)
        group_keys = groups.keys.clone()

        # For each group that does already exist in cloud
        cloud_groups = describe_security_groups(vpc_id)
        cloud_groups.each do |cloud_group|
          group_name = cloud_group[:name]
          group_id = cloud_group[:group_id]

          # skip those groups that don't belong to this project/env
          next if env.isolate_security_groups && group_name !~ /^#{isolate_prefix}/

          if group_keys.delete(group_name)
            # sync rules
            capistrano.logger.debug "Security Group already in cloud, syncing rules: #{group_name}"
            group = groups[group_name]

            # Convert the special case default rule into what it actually looks like when
            # we query ec2 so that we can match things up when syncing.  Also,
            # retain a reference to the default rule so we can add the source_group_id
            # when we sync from the cloud
            default_rules = []

            rules = group['rules'].clone
            group['rules'].each do |rule|
              if [2, 3].include?(rule.size) && rule['source_group_name'] && rule['source_group_account']
                # source_group_id value will be populated when we fetch rules from the cloud
                # TODO we appear to have a mismatch on source_group_account for some reason
                default_rule = rule.merge({
                                            "source_group_id" => nil,
                                            "protocol" => "-1",
                                            "from_port" => "",
                                            "to_port" => ""
                                          })
                rules << default_rule
                default_rules << default_rule
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
                  rule_map[:source_group_id] = source_group[:group_id]
                  rule_map[:source_group_account] = source_group[:account]

                  # Update the special case default rule with the group id if
                  # appropriate
                  if (rule_map[:protocol] == "-1") && rule_map[:to_port].nil? && rule_map[:from_port].nil?
                    default_rules.each do |default_rule|
                      if default_rule['source_group_account'] == source_group[:account]
                        default_rule['source_group_id'] = rule_map[:source_group_id]
                      end
                    end
                  end

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
                  if rule_map[:source_group_id]
                    remove_security_group_rule(group_id, rule_map[:protocol], rule_map[:from_port], rule_map[:to_port], {:id => rule_map[:source_group_id], :account => rule_map[:source_group_account]})
                  else
                    rule_map[:source_ips].each do |source_ip|
                      remove_security_group_rule(group_id, rule_map[:protocol], rule_map[:from_port], rule_map[:to_port], source_ip)
                    end if rule_map[:source_ips]
                  end
                end
              end
            end

            rules.each do |rule_map|
              # create non-existing rules
              capistrano.logger.debug "Missing rule, creating: #{rule_map.inspect}"
              rule_map = Rubber::Util::symbolize_keys(rule_map)
              if rule_map[:source_group_id]
                add_security_group_rule(group_id, rule_map[:protocol], rule_map[:from_port], rule_map[:to_port], {:id => rule_map[:source_group_id], :account => rule_map[:source_group_account]})
              else
                rule_map[:source_ips].each do |source_ip|
                  add_security_group_rule(group_id, rule_map[:protocol], rule_map[:from_port], rule_map[:to_port], source_ip)
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
          new_group = create_security_group(vpc_id, group_name, group['description'])
          group_id = new_group.group_id
          # create rules for group
          group['rules'].each do |rule_map|
            capistrano.logger.debug "Creating new rule: #{rule_map.inspect}"
            rule_map = Rubber::Util::symbolize_keys(rule_map)
            if rule_map[:source_group_name]
              add_security_group_rule(group_id, rule_map[:protocol], rule_map[:from_port], rule_map[:to_port], {:id => rule_map[:source_group_id], :account => rule_map[:source_group_account]})
            else
              rule_map[:source_ips].each do |source_ip|
                add_security_group_rule(group_id, rule_map[:protocol], rule_map[:from_port], rule_map[:to_port], source_ip)
              end if rule_map[:source_ips]
            end
          end
        end
      end

      def load_bound_env
        rubber_cfg = Rubber::Configuration.get_configuration(Rubber.env)
        scoped_env = rubber_cfg.environment.bind(nil, [])
      end

      def subnet_for_availability_zone(bound_env, availability_zone, is_public)
        vpc_cfg = bound_env.rubber_instances.artifacts['vpc']

        return nil unless vpc_cfg
        return nil unless vpc_cfg.has_key? 'instance_subnets'

        public_private = is_public ? "public" : "private"

        vpc_cfg['instance_subnets'][public_private].find do |s|
          s['availability_zone'] == availability_zone
        end
      end

      def get_vpc_id(bound_env)
        vpc_cfg = bound_env.rubber_instances.artifacts['vpc']

        vpc_cfg && vpc_cfg['id']
      end

      def add_vpc_to_instance_file(bound_env, vpc)
        bound_env.rubber_instances.artifacts['vpc'] = {
          'id' => vpc.id
        }

        bound_env.rubber_instances.save
      end

      def add_subnet_to_instance_file(bound_env, subnet, is_public)
        subnet_cfg = instance_subnets(bound_env)

        subnet_cfg[is_public ? "public" : "private"]  <<  {
          'availability_zone' => subnet.availability_zone,
          'subnet_id' => subnet.subnet_id,
          'cidr' => subnet.cidr_block
        }

        bound_env.rubber_instances.save
      end

      def instance_subnets(bound_env)
        bound_env.rubber_instances.artifacts['vpc']['instance_subnets'] ||= {
          "public" => [],
          "private" => []
        }
      end
    end
  end
end

