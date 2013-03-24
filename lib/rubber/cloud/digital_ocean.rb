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

    end
  end
end
