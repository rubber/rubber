require 'rubber/cloud/aws/base'
require 'rubber/util'

module Rubber
  module Cloud
  
    class Aws::Vpc < Aws::Base

      def before_create_instance(instance)
        host_env = load_bound_env(instance.name)

        role_names = instance.roles.map(&:name)
        instance.vpc_id = setup_vpc(instance.vpc_alias, instance.vpc_cidr).id
        instance.gateway = host_env.private_nic.gateway
        private_public = instance.gateway == 'public' ? 'public' : 'private'

        instance.subnet_id = setup_vpc_subnet(
          instance.vpc_id,
          instance.vpc_alias,
          host_env.private_nic,
          instance.zone,
          "#{instance.vpc_alias} #{instance.zone} #{private_public}"
        ).subnet_id

        setup_security_groups(instance.vpc_id, instance.name, instance.role_names)
      end

      def after_create_instance(instance)
        super

        # Creating an instance with both a subnet id and groups doesn't seem to
        # result in the groups actually sticking.  Lucky, VPC instances have
        # mutable security groups
        group_ids = describe_security_groups(instance.vpc_id).map { |g|
          if instance.security_groups.include?(g[:name])
            g[:group_id]
          else
            nil
          end
        }.compact

        compute_provider.modify_instance_attribute(instance.instance_id, {
                                                     'GroupId' => group_ids
                                                   })

        if instance.roles.map(&:name).include? "nat_gateway"
          # NAT gateways need the sourceDestCheck attribute to be false for AWS
          # to allow them to route traffic
          server = compute_provider.servers.get(instance.instance_id)

          server.network_interfaces.each do |interface|
            # Sometimes we get a blank interface back
            next unless interface.count > 0

            interface_id = interface['networkInterfaceId']

            compute_provider.modify_network_interface_attribute(
              interface_id,
              'sourceDestCheck',
              false
            )
          end
        end
      end

      def setup_security_groups(vpc_id, host=nil, roles=[])
        rubber_cfg = Rubber::Configuration.get_configuration(Rubber.env)
        scoped_env = rubber_cfg.environment.bind(roles, host)
        security_group_defns = Hash[scoped_env.security_groups.to_a]

        if scoped_env.auto_security_groups
          sghosts = (scoped_env.rubber_instances.collect{|ic| ic.name } + [host]).uniq.compact
          sgroles = (scoped_env.rubber_instances.all_roles + roles).uniq.compact
          security_group_defns = inject_auto_security_groups(security_group_defns, sghosts, sgroles)
        end

        sync_security_groups(vpc_id, security_group_defns)
      end

      def setup_vpc(vpc_alias, vpc_cidr)
        bound_env = load_bound_env

        # First, check to see if the VPC is defined in the instance file.  If it
        # isn't, then check AWS for any VPCs with the same tag:RubberAlias.
        # Failing that, create it

        vpc = compute_provider.vpcs.all("tag:RubberAlias" => vpc_alias).first
        vpc_id = vpc && vpc.id

        if vpc_id
          capistrano.logger.debug "Using #{vpc_id} #{vpc_alias}"
        else
          vpc = create_vpc(
            "#{bound_env.app_name} #{Rubber.env}",
            vpc_alias,
            vpc_cidr
          )

          vpc_id = vpc.id

          capistrano.logger.debug "Created #{vpc_id} #{vpc_alias}"
        end

        vpc
      end

      def setup_vpc_subnet(vpc_id, vpc_alias, private_nic, availability_zone, name)
        subnet = find_or_create_vpc_subnet(
          vpc_id,
          vpc_alias,
          name,
          availability_zone,
          private_nic.subnet_cidr,
          private_nic.gateway
        )

        capistrano.logger.debug "Using #{subnet.subnet_id} #{name}"

        subnet
      end

      def destroy_vpc(vpc_alias)
        %w[
           subnets
           route_tables
           security_groups
           internet_gateways 
        ].each do |resource_name|
          destroy_vpc_resource(vpc_alias, resource_name.strip)
        end

        vpc = compute_provider.vpcs.all('tag:RubberAlias' => vpc_alias).first
        if vpc
          compute_provider.vpcs.destroy(vpc.id)

          capistrano.logger.info "Destroyed #{vpc.id} #{vpc_alias}"
        else
          capistrano.logger.info "No VPC found with alias #{vpc_alias}"
        end
      end

      def destroy_internet_gateways(vpc_alias)
        vpc = compute_provider.vpcs.all("tag:RubberAlias" => vpc_alias).first
        gateways = compute_provider.internet_gateways.all('tag:RubberVpcAlias' => vpc_alias)

        gateways.each do |gateway|
          compute_provider.detach_internet_gateway(gateway.id, vpc.id)

          sleep 5

          gateway.reload

          if gateway.attachment_set.length > 0
            compute_provider.delete_tags gateway.id, { "RubberVpcAlias" => vpc_alias }
            capistrano.logger.info "not destroying #{gateway.id} due to other VPC attachments"
          else
            gateway.destroy
          end
        end

        capistrano.logger.info "destroyed internet_gateways"
      end

      def destroy_security_groups(vpc_alias)
        vpc = compute_provider.vpcs.all("tag:RubberAlias" => vpc_alias).first

        groups = compute_provider.security_groups.all('vpc-id' => vpc.id)

        groups.all.each do |group|
          begin
            group.destroy
          rescue ::Fog::Compute::AWS::Error => e
            # Some groups cannot be deleted by users.  Just ignore these
            raise e unless e.message =~ /CannotDelete/
          end
        end

        capistrano.logger.info "destroyed security_groups"
      end

      def destroy_vpc_resource(vpc_alias, resource_name_plural)
        specific_call = "destroy_#{resource_name_plural}"

        if self.respond_to? specific_call
          should_destroy = self.send specific_call, vpc_alias
        else
          resources = compute_provider.send(resource_name_plural).all('tag:RubberVpcAlias' => vpc_alias)

          resources.each(&:destroy)

          capistrano.logger.info "destroyed #{resource_name_plural}"
        end
      end

      def describe_security_groups(vpc_id, group_name=nil)
        groups = []

        # As of 10/2/2015, vpcId isn't a valid filter, so we have to filter
        # manually
        opts = {
          'vpc-id' => vpc_id
        }
        opts["group-name"] = group_name if group_name
        response = compute_provider.security_groups.all(opts)

        response.each do |item|
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

      private

      def create_vpc(name, vpc_alias, subnet_str)
        vpc = compute_provider.vpcs.create(:cidr_block => subnet_str)

        Rubber::Util.retry_on_failure(StandardError, :retry_sleep => 1, :retry_count => 120) do
          create_tags(vpc.id,
                      :Name => name,
                      :Environment => Rubber.env,
                      :RubberAlias => vpc_alias)
        end

        vpc
      end

      def find_or_create_vpc_subnet(vpc_id, vpc_alias, name, availability_zone, cidr_block, gateway)
        unless Rubber::Util.is_instance_id?(gateway) ||
               Rubber::Util.is_internet_gateway_id?(gateway) ||
               (gateway == 'public')
          raise "gateway must be an instance id, gateway id, or \"public\""
        end

        subnet = compute_provider.subnets.all(
          'tag:RubberVpcAlias' => vpc_alias,
          'cidr-block' => cidr_block,
          'availability-zone' => availability_zone
        ).first

        unless subnet
          subnet = compute_provider.subnets.create :vpc_id => vpc_id,
                                                   :cidr_block => cidr_block,
                                                   :availability_zone => availability_zone


          Rubber::Util.retry_on_failure(StandardError, :retry_sleep => 1, :retry_count => 120) do
            create_tags(subnet.subnet_id,
                        'Name' => name,
                        'Environment' => Rubber.env,
                        'RubberVpcAlias' => vpc_alias
                       )
          end

          route_table = compute_provider.route_tables.all(
            'vpc-id' => vpc_id,
            'association.subnet-id' => subnet.subnet_id,
            'tag:RubberVpcAlias' => vpc_alias
          ).first

          route_table_id = route_table && route_table.id

          unless route_table_id
            resp = compute_provider.create_route_table(vpc_id)

            route_table_id = resp.body['routeTable'].first['routeTableId']

            Rubber::Util.retry_on_failure(StandardError, :retry_sleep => 1, :retry_count => 120) do
              create_tags(
                route_table_id,
                'Name' => name,
                'Environment' => Rubber.env,
                'RubberVpcAlias' => vpc_alias,
                'Public' => (gateway == 'public')
              )
            end

            compute_provider.associate_route_table(route_table_id, subnet.subnet_id)
          end

          if Rubber::Util.is_instance_id?(gateway)
            compute_provider.create_route(route_table_id, "0.0.0.0/0", nil, gateway)
          elsif Rubber::Util.is_internet_gateway_id?(gateway)
            compute_provider.create_route(route_table_id, "0.0.0.0/0", gateway)
          else
            internet_gateway = find_or_create_vpc_internet_gateway(vpc_id, vpc_alias, "#{name} gateway")

            compute_provider.create_route(route_table_id, "0.0.0.0/0", internet_gateway.id)

            capistrano.logger.debug "Created #{subnet.subnet_id} #{name}"
          end
        end

        subnet
      end

      def find_or_create_vpc_internet_gateway(vpc_id, vpc_alias, name)
        gateway = compute_provider.internet_gateways.all(
          'tag:RubberVpcAlias' => vpc_alias
        ).first

        unless gateway
          gateway = compute_provider.internet_gateways.create
          gateway.attach(vpc_id)
          Rubber::Util.retry_on_failure(StandardError, :retry_sleep => 1, :retry_count => 120) do
            create_tags(
              gateway.id,
              'Name' => name,
              'Environment' => Rubber.env,
              'RubberVpcAlias' => vpc_alias
            )
          end

          capistrano.logger.debug "Created #{gateway.id} #{name}"
        end

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
        to_port = 65535 if to_port.nil?

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

      def load_bound_env(host=nil)
        rubber_cfg = Rubber::Configuration.get_configuration(Rubber.env)
        scoped_env = rubber_cfg.environment.bind(nil, host)
      end
    end
  end
end

