require 'rubber/cloud/fog'
require 'rubber/cloud/aws_table_store'

module Rubber
  module Cloud
  
    class Aws < Fog
      
      def initialize(env, capistrano)
        
        compute_credentials = {
          :aws_access_key_id => env.access_key,
          :aws_secret_access_key => env.secret_access_key
        }

        storage_credentials = {
          :provider => 'AWS',
          :aws_access_key_id => env.access_key,
          :aws_secret_access_key => env.secret_access_key,
          :path_style => true
        }

        @table_store = ::Fog::AWS::SimpleDB.new(compute_credentials)
        
        compute_credentials[:region] = env.region
        @elb = ::Fog::AWS::ELB.new(compute_credentials)

        compute_credentials[:provider] = 'AWS' # We need to set the provider after the SimpleDB init because it fails if the provider value is specified.

        storage_credentials[:region] = env.region

        env['compute_credentials'] = compute_credentials
        env['storage_credentials'] = storage_credentials
        super(env, capistrano)
      end
      
      def table_store(table_key)
        return Rubber::Cloud::AwsTableStore.new(@table_store, table_key)  
      end

      def describe_instances(instance_id=nil)
        instances = []
        opts = {}
        opts["instance-id"] = instance_id if instance_id

        response = compute_provider.servers.all(opts)
        response.each do |item|
          instance = {}
          instance[:id] = item.id
          instance[:type] = item.flavor_id
          instance[:external_host] = item.dns_name
          instance[:external_ip] = item.public_ip_address
          instance[:internal_host] = item.private_dns_name
          instance[:internal_ip] = item.private_ip_address
          instance[:state] = item.state
          instance[:zone] = item.availability_zone
          instance[:provider] = 'aws'
          instance[:platform] = item.platform || Rubber::Platforms::LINUX
          instance[:root_device_type] = item.root_device_type
          instances << instance
        end

        return instances
      end

      def active_state
        'running'
      end

      def stopped_state
        'stopped'
      end

      def before_create_instance(instance_alias, role_names)
        setup_security_groups(instance_alias, role_names)
      end

      def after_create_instance(instance)
        # Sometimes tag creation will fail, indicating that the instance doesn't exist yet even though it does.  It seems to
        # be a propagation delay on Amazon's end, so the best we can do is wait and try again.
        Rubber::Util.retry_on_failure(StandardError, :retry_sleep => 1, :retry_count => 120) do
          Rubber::Tag::update_instance_tags(instance.name)
        end
      end

      def after_refresh_instance(instance)
        # Sometimes tag creation will fail, indicating that the instance doesn't exist yet even though it does.  It seems to
        # be a propagation delay on Amazon's end, so the best we can do is wait and try again.
        Rubber::Util.retry_on_failure(StandardError, :retry_sleep => 1, :retry_count => 120) do
          Rubber::Tag::update_instance_tags(instance.name)
        end
      end

      def before_stop_instance(instance)
        capistrano.fatal "Cannot stop spot instances!" if ! instance.spot_instance_request_id.nil?
        capistrano.fatal "Cannot stop instances with instance-store root device!" if (instance.root_device_type != 'ebs')
      end

      def before_start_instance(instance)
        capistrano.fatal "Cannot start spot instances!" if ! instance.spot_instance_request_id.nil?
        capistrano.fatal "Cannot start instances with instance-store root device!" if (instance.root_device_type != 'ebs')
      end

      def after_start_instance(instance)
        # Re-starting an instance will almost certainly give it a new set of IPs and DNS entries, so refresh the values.
        capistrano.rubber.refresh_instance(instance.name)

        # Static IPs, DNS, etc. need to be set up for the started instance.
        capistrano.rubber.post_refresh
      end

      def create_image(image_name)

        # validate all needed config set
        ["key_file", "pk_file", "cert_file", "account", "secret_access_key", "image_bucket"].each do |k|
          raise "Set #{k} in rubber.yml" unless "#{env[k]}".strip.size > 0
        end
        raise "create_image can only be called from a capistrano scope" unless capistrano
 
        ec2_key = env.key_file
        ec2_pk = env.pk_file
        ec2_cert = env.cert_file

        ec2_key_dest = "/mnt/#{File.basename(ec2_key)}"
        ec2_pk_dest = "/mnt/#{File.basename(ec2_pk)}"
        ec2_cert_dest = "/mnt/#{File.basename(ec2_cert)}"

        storage(env.image_bucket).ensure_bucket
        
        capistrano.put(File.read(ec2_key), ec2_key_dest)
        capistrano.put(File.read(ec2_pk), ec2_pk_dest)
        capistrano.put(File.read(ec2_cert), ec2_cert_dest)

        arch = capistrano.capture("uname -m").strip
        arch = case arch when /i\d86/ then "i386" else arch end

        capistrano.sudo_script "create_bundle", <<-CMD
          export RUBYLIB=/usr/lib/site_ruby/
          unset RUBYOPT
          nohup ec2-bundle-vol --batch -d /mnt -k #{ec2_pk_dest} -c #{ec2_cert_dest} -u #{env.account} -p #{image_name} -r #{arch} &> /tmp/ec2-bundle-vol.log &
          bg_pid=$!
          sleep 1

          echo "Creating image from instance volume..."
          while kill -0 $bg_pid &> /dev/null; do
            echo -n .
            sleep 5
          done
          
          # this returns exit code even if pid has already died, and thus triggers fail fast shell error
          wait $bg_pid
        CMD

        capistrano.sudo_script "register_bundle", <<-CMD
          export RUBYLIB=/usr/lib/site_ruby/
          unset RUBYOPT
          echo "Uploading image to S3..."
          ec2-upload-bundle --batch -b #{env.image_bucket} -m /mnt/#{image_name}.manifest.xml -a #{env.access_key} -s #{env.secret_access_key}
        CMD

        image_location = "#{env.image_bucket}/#{image_name}.manifest.xml"
        response = compute_provider.register_image(image_name,
                                                    "rubber bundled image",
                                                    image_location)
        return response.body["imageId"]
      end

      def destroy_image(image_id)
        image = compute_provider.images.get(image_id)
        raise "Could not find image: #{image_id}, aborting destroy_image" if image.nil?

        location_parts = image.location.split('/')
        bucket = location_parts.first
        image_name = location_parts.last.gsub(/\.manifest\.xml$/, '')

        image.deregister

        storage(bucket).walk_tree(image_name) do |f|
          f.destroy
        end
      end

      def describe_load_balancers(name=nil)
        lbs = []
        response = name.nil? ? @elb.load_balancers.all() : [@elb.load_balancers.get(name)].compact
        response.each do |item|
          lb = {}
          lb[:name] = item.id
          lb[:dns_name] = item.dns_name
          lb[:zones] = item.availability_zones

          item.listeners.each do |litem|
            listener = {}
            listener[:protocol] = litem.protocol
            listener[:port] = litem.lb_portPort
            listener[:instance_port] = litem.instance_port
            lb[:listeners] ||= []
            lb[:listeners] << listener
          end

          lbs << lb
        end
        return lbs
      end

      def describe_availability_zones
        zones = []
        response = compute_provider.describe_availability_zones()
        items = response.body["availabilityZoneInfo"]
        items.each do |item|
          zone = {}
          zone[:name] = item["zoneName"]
          zone[:state] =item["zoneState"]
          zones << zone
        end
        return zones
      end

      def create_spot_instance_request(spot_price, ami, ami_type, security_groups, availability_zone)
        response = compute_provider.spot_requests.create(:price => spot_price,
                                                          :image_id => ami,
                                                          :flavor_id => ami_type,
                                                          :groups => security_groups,
                                                          :availability_zone => availability_zone,
                                                          :key_name => env.key_name)
        request_id = response.id
        return request_id
      end

      def describe_spot_instance_requests(request_id=nil)
        requests = []
        opts = {}
        opts["spot-instance-request-id"] = request_id if request_id
        response = compute_provider.spot_requests.all(opts)
        response.each do |item|
          request = {}
          request[:id] = item.id
          request[:spot_price] = item.price
          request[:state] = item.state
          request[:created_at] = item.created_at
          request[:type] = item.flavor_id
          request[:image_id] = item.image_id
          request[:instance_id] = item.instance_id
          requests << request
        end
        return requests
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

        sync_security_groups(security_group_defns)
      end

      def describe_security_groups(group_name=nil)
        groups = []

        opts = {}
        opts["group-name"] = group_name if group_name
        response = compute_provider.security_groups.all(opts)

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
              source_group[:name] = rule_group["groupName"]
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
        volume = compute_provider.volumes.create(:size => volume_spec['size'], :availability_zone => volume_spec['zone'])
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

      def create_security_group(group_name, group_description)
        compute_provider.security_groups.create(:name => group_name, :description => group_description)
      end

      def destroy_security_group(group_name)
        compute_provider.security_groups.get(group_name).destroy
      end

      def add_security_group_rule(group_name, protocol, from_port, to_port, source)
        group = compute_provider.security_groups.get(group_name)
        opts = {:ip_protocol => protocol || 'tcp'}

        if source.instance_of? Hash
          opts[:group] = {source[:account] => source[:name]}
        else
          opts[:cidr_ip] = source
        end

        group.authorize_port_range(from_port.to_i..to_port.to_i, opts)
      end

      def remove_security_group_rule(group_name, protocol, from_port, to_port, source)
        group = compute_provider.security_groups.get(group_name)
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
        cloud_groups = describe_security_groups()
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
