require 'rubber/cloud/fog'

module Rubber
  module Cloud

    class DigitalOcean < Fog

      def initialize(env, capistrano)
        compute_credentials = {
          :provider => 'DigitalOcean',
          :digitalocean_api_key => env.api_key,
          :digitalocean_client_id => env.client_key
        }

        if env.cloud_providers && env.cloud_providers.aws
          storage_credentials = {
            :provider => 'AWS',
            :aws_access_key_id => env.cloud_providers.aws.access_key,
            :aws_secret_access_key => env.cloud_providers.aws.secret_access_key
          }

          env['storage_credentials'] = storage_credentials
        end

        env['compute_credentials'] = compute_credentials
        super(env, capistrano)
      end

      def create_instance(instance_alias, image_name, image_type, security_groups, availability_zone)
        region = compute_provider.regions.find { |r| r.name == availability_zone }
        if region.nil?
          raise "Invalid region for DigitalOcean: #{availability_zone}"
        end

        image = compute_provider.images.find { |i| i.name == image_name }
        if image.nil?
          raise "Invalid image name for DigitalOcean: #{image_name}"
        end

        flavor = compute_provider.flavors.find { |f| f.name == image_type }
        if flavor.nil?
          raise "Invalid image type for DigitalOcean: #{image_type}"
        end

        # Check if the SSH key has been added to DigitalOcean yet.
        # TODO (nirvdrum 03/23/13): DigitalOcean has an API for getting a single SSH key, but it hasn't been added to fog yet.  We should add it.
        ssh_key = compute_provider.list_ssh_keys.body['ssh_keys'].find { |key| key['name'] == env.key_name }
        if ssh_key.nil?
          if env.key_file
            ssh_key = compute_provider.create_ssh_key(env.key_name, File.read("#{env.key_file}.pub"))
          else
            raise 'Missing key_file for DigitalOcean'
          end
        end

        response = compute_provider.servers.create(:name => "#{Rubber.env}-#{instance_alias}",
                                                   :image_id => image.id,
                                                   :flavor_id => flavor.id,
                                                   :region_id => region.id,
                                                   :ssh_key_ids => [ssh_key['id']])

        response.id
      end

      def describe_instances(instance_id=nil)
        instances = []
        opts = {}

        if instance_id
          response = [compute_provider.servers.get(instance_id)]
        else
          response = compute_provider.servers.all(opts)
        end

        response.each do |item|
          instance = {}
          instance[:id] = item.id
          instance[:state] = item.state
          instance[:type] = item.flavor_id
          instance[:external_ip] = item.ip_address
          instance[:internal_ip] = item.ip_address
          instance[:region_id] = item.region_id
          instance[:provider] = 'digital_ocean'
          instance[:platform] = 'linux'
          instances << instance
        end

        return instances
      end

      def active_state
        'active'
      end

      def after_refresh_instance(instance)
        setup_security_groups(instance.name, instance.role_names)
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
              (from_port..to_port).each do |port|
                source_ips.each do |source|
                  script << "\niptables -A INPUT -p #{protocol} --dport #{port} --source #{source} -j ACCEPT -m comment --comment '#{group_name}'"
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
