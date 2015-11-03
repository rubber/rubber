require 'ext/fog/compute/digital_ocean_v2'
require 'rubber/cloud/fog'

module Rubber
  module Cloud

    class DigitalOcean < Fog

      def initialize(env, capistrano)
        compute_credentials = {
          :provider => 'DigitalOcean',
          :version => 'v2',
          :digitalocean_token => env.digital_ocean_token,
        }

        if env.cloud_providers && env.cloud_providers.aws
          storage_credentials = {
            :provider => 'AWS',
            :aws_access_key_id => env.cloud_providers.aws.access_key,
            :aws_secret_access_key => env.cloud_providers.aws.secret_access_key,
            :path_style => true
          }

          storage_credentials[:region] = env.cloud_providers.aws.region

          env['storage_credentials'] = storage_credentials
        end

        env['compute_credentials'] = compute_credentials
        super(env, capistrano)
      end

      def create_instance(instance_alias, image_name, image_type, security_groups, availability_zone, region, fog_options={})
        do_region = compute_provider.regions.find { |r| [r.name, r.slug].include?(region) }
        if do_region.nil?
          raise "Invalid region for DigitalOcean: #{region}"
        end

        if env.private_networking && ! do_region.features.include?("private_networking")
          raise "Private networking is enabled, but region #{region} does not support it"
        end

        image = compute_provider.images.find { |i| i.name == image_name }
        if image.nil?
          raise "Invalid image name for DigitalOcean: #{image_name}"
        end

        # Downcase image_type for backward compatability with v1
        flavor = compute_provider.flavors.find { |f| f.slug == image_type.downcase }

        if flavor.nil?
          raise "Invalid image type for DigitalOcean: #{image_type}"
        end

        if env.key_name.nil?
          raise 'missing key_name for DigitalOcean'
        end

        # Check if the SSH key has been added to DigitalOcean yet.
        # TODO (nirvdrum 03/23/13): DigitalOcean has an API for getting a single SSH key, but it hasn't been added to fog yet.  We should add it.
        ssh_key = compute_provider.list_ssh_keys.body['ssh_keys'].find { |key| key['name'] == env.key_name }
        if ssh_key.nil?
          if env.key_file
            compute_provider.create_ssh_key(env.key_name, File.read("#{env.key_file}.pub"))

            # Although not documented, DigitalOcean is eventually consistent.  Receiving a 200 response with the key
            # body does not mean the key has propagated through their systems yet.  Thus we need to query to see if
            # the key is yet available.  Otherwise our request will end up creating a droplet without an attached key.

            begin
              sleep(0.5)
              ssh_key = compute_provider.list_ssh_keys.body['ssh_keys'].find { |key| key['name'] == env.key_name }
            end while ssh_key.nil?

          else
            raise 'Missing key_file for DigitalOcean'
          end
        end

        response = compute_provider.servers.create({:name => "#{Rubber.env}-#{instance_alias}",
                                                    :image => image.slug,
                                                    :size => flavor.slug,
                                                    :flavor => flavor.slug,
                                                    :region => do_region.slug,
                                                    :ssh_keys => [ssh_key['id']],
                                                    :private_networking => (env.private_networking.to_s.downcase == 'true')
                                                   }
                                                    .merge(Rubber::Util.symbolize_keys(fog_options))
                                                  )

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
          instance[:type] = item.size_slug

          public_networking_info = item.networks['v4'].find { |n|
            n['type'] == 'public'
          }

          if public_networking_info
            instance[:external_ip] = public_networking_info['ip_address']
          end

          private_networking_info = item.networks['v4'].find { |n|
            n['type'] == 'private'
          }

          if private_networking_info
            instance[:internal_ip] = private_networking_info['ip_address']
          elsif public_networking_info
            instance[:internal_ip] = public_networking_info['ip_address']
          end

          instance[:region_id] = item.region
          instance[:provider] = 'digital_ocean'
          instance[:platform] = Rubber::Platforms::LINUX
          instances << instance
        end

        return instances
      end

      def active_state
        'active'
      end

      def destroy_instance(instance_id)
        # The Digital Ocean API will return a 422 if we attempt to destroy an
        # instance that's in the middle of booting up, so wait until it's
        # in a non-"new" state
        print "Waiting for non-new instance state"

        loop do
          instance = describe_instances(instance_id).first

          print "."

          break unless instance[:state] == "new"

          sleep 1
        end

        response = compute_provider.servers.get(instance_id).delete()
      end
    end
  end
end
