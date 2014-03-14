require 'fog'
require 'rubber/cloud/fog_storage'

module Rubber
  module Cloud
  
    class Fog < Base

      def initialize(env, capistrano)
        super(env, capistrano)

        @compute_credentials = Rubber::Util.symbolize_keys(env.compute_credentials) if env.compute_credentials
        @storage_credentials = Rubber::Util.symbolize_keys(env.storage_credentials) if env.storage_credentials
      end

      def compute_provider
        @compute_provider ||= @compute_credentials ? ::Fog::Compute.new(@compute_credentials) : nil
      end

      def storage_provider
        @storage_provider ||= @storage_credentials ? ::Fog::Storage.new(@storage_credentials) : nil
      end

      def storage(bucket)
        return Rubber::Cloud::FogStorage.new(storage_provider, bucket)
      end

      def table_store(table_key)
        raise NotImplementedError, "No table store available for generic fog adapter"
      end

      def create_instance(instance_alias, ami, ami_type, security_groups, availability_zone, region)
        response = compute_provider.servers.create(:image_id => ami,
                                                   :flavor_id => ami_type,
                                                   :groups => security_groups,
                                                   :availability_zone => availability_zone,
                                                   :key_name => env.key_name,
                                                   :name => instance_alias)

        response.id
      end

      def destroy_instance(instance_id)
        response = compute_provider.servers.get(instance_id).destroy()
      end

      def destroy_spot_instance_request(request_id)
        compute_provider.spot_requests.get(request_id).destroy
      end
  
      def reboot_instance(instance_id)
        compute_provider.servers.get(instance_id).reboot()
      end

      def stop_instance(instance, force=false)
        # Don't force the stop process. I.e., allow the instance to flush its file system operations.
        compute_provider.servers.get(instance.instance_id).stop(force)
      end

      def start_instance(instance)
        compute_provider.servers.get(instance.instance_id).start()
      end

      def create_static_ip
        address = compute_provider.addresses.create()

        address.public_ip
      end

      def attach_static_ip(ip, instance_id)
        address = compute_provider.addresses.get(ip)
        server = compute_provider.servers.get(instance_id)
        response = (address.server = server)

        ! response.nil?
      end

      def detach_static_ip(ip)
        address = compute_provider.addresses.get(ip)
        response = (address.server = nil)

        ! response.nil?
      end

      def describe_static_ips(ip=nil)
        ips = []
        opts = {}
        opts["public-ip"] = ip if ip
        response = compute_provider.addresses.all(opts)
        response.each do |item|
          ip = {}
          ip[:instance_id] = item.server_id
          ip[:ip] = item.public_ip
          ips << ip
        end

        ips
      end

      def destroy_static_ip(ip)
        address = compute_provider.addresses.get(ip)
        address.destroy
      end

      def create_image(image_name)
        raise NotImplementedError, "create_image not implemented in generic fog adapter"
      end

      def describe_images(image_id=nil)
        images = []
        opts = {"Owner" => "self"}
        opts["image-id"] = image_id if image_id
        response = compute_provider.images.all(opts)
        response.each do |item|
          image = {}
          image[:id] = item.id
          image[:location] = item.location
          image[:root_device_type] = item.root_device_type
          images << image
        end

        images
      end

      def destroy_image(image_id)
        raise NotImplementedError, "destroy_image not implemented in generic fog adapter"
      end

      def describe_load_balancers(name=nil)
        raise NotImplementedError, "describe_load_balancers not implemented in generic fog adapter"
      end

      def before_create_volume(instance, volume_spec)
        # No-op by default.
      end

      def create_volume(instance, volume_spec)
        # No-op by default.
      end

      def after_create_volume(instance, volume_id, volume_spec)
        # No-op by default.
      end

      def before_destroy_volume(volume_id)
        # No-op by default.
      end

      def destroy_volume(volume_id)
        # No-op by default.
      end

      def after_destroy_volume(volume_id)
        # No-op by default.
      end

      def should_destroy_volume_when_instance_destroyed?
        false
      end
    end

  end
end
