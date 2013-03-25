require 'rubber/cloud/fog'

module Rubber
  module Cloud

    class DigitalOcean < Fog

      def initialize(env, capistrano)

        credentials = {
            :digitalocean_api_key => env.api_key,
            :digitalocean_client_id => env.client_key
        }

        credentials[:provider] = 'DigitalOcean'
        env['credentials'] = credentials
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
          instance[:state] = item.status
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

      def create_security_group_phase
        :after_instance_create
      end

      def create_security_group(host, group_name, group_description)
      end

      def describe_security_groups(hosts=nil, group_name=nil)
        rules = capistrano.capture("iptables -S INPUT", :hosts => hosts).strip.split("\r\n")
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

      def start_adding_security_group_rules(hosts)
        script = <<-ENDSCRIPT
          # Clear out all firewall rules to start.
          iptables -F

          iptables -I INPUT 1 -i lo -j ACCEPT -m comment --comment 'Enable connections on loopback devices.'
          iptables -I INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT -m comment --comment 'Always allow established connections to remain connected.'
        ENDSCRIPT

        capistrano.run_script 'start_adding_firewall_rules', script, :hosts => hosts
      end

      def add_security_group_rule(hosts, group_name, protocol, from_port, to_port, source)
        if protocol && from_port && to_port && source
          (from_port..to_port).each do |port|
            capistrano.sudo "iptables -A INPUT -p #{protocol} --dport #{port} --source #{source} -j ACCEPT -m comment --comment '#{group_name}'", :hosts => hosts
          end
        end
      end

      def done_adding_security_group_rules(hosts)
        # Add the REJECT rule last.
        capistrano.sudo "iptables -A INPUT -j DROP -m comment --comment 'Disable all other connections.'", :hosts => hosts
      end
    end
  end
end
