require 'fog'
require 'rubber/cloud/fog_storage'

module Rubber
  module Cloud
  
    class Fog < Base
      
      attr_reader :compute_provider, :storage_provider

      def initialize(env, capistrano)
        super(env, capistrano)
        credentials = Rubber::Util.symbolize_keys(env.credentials)
        @compute_provider = ::Fog::Compute.new(credentials)

        # TODO (nirvdrum: 03/23/13) Not all providers have a storage provider.  We need to support mixing and matching.
        @storage_provider = ::Fog::Storage.new(credentials) rescue nil
      end
      
      def storage(bucket)
        return Rubber::Cloud::FogStorage.new(@storage_provider, bucket)
      end

      def table_store(table_key)
        raise NotImplementedError, "No table store available for generic fog adapter"
      end

      def create_instance(instance_alias, ami, ami_type, security_groups, availability_zone)
        response = @compute_provider.servers.create(:image_id => ami,
                                                    :flavor_id => ami_type,
                                                    :groups => security_groups,
                                                    :availability_zone => availability_zone,
                                                    :key_name => env.key_name)
        instance_id = response.id
        return instance_id
      end

      def destroy_instance(instance_id)
        response = @compute_provider.servers.get(instance_id).destroy()
      end

      def destroy_spot_instance_request(request_id)
        @compute_provider.spot_requests.get(request_id).destroy
      end
  
      def reboot_instance(instance_id)
        response = @compute_provider.servers.get(instance_id).reboot()
      end

      def stop_instance(instance_id, force=false)
        # Don't force the stop process. I.e., allow the instance to flush its file system operations.
        response = @compute_provider.servers.get(instance_id).stop(force)
      end

      def start_instance(instance_id)
        response = @compute_provider.servers.get(instance_id).start()
      end

      def create_static_ip
        address = @compute_provider.addresses.create()
        return address.public_ip
      end

      def attach_static_ip(ip, instance_id)
        address = @compute_provider.addresses.get(ip)
        server = @compute_provider.servers.get(instance_id)
        response = (address.server = server)
        return ! response.nil?
      end

      def detach_static_ip(ip)
        address = @compute_provider.addresses.get(ip)
        response = (address.server = nil)
        return ! response.nil?
      end

      def describe_static_ips(ip=nil)
        ips = []
        opts = {}
        opts["public-ip"] = ip if ip
        response = @compute_provider.addresses.all(opts)
        response.each do |item|
          ip = {}
          ip[:instance_id] = item.server_id
          ip[:ip] = item.public_ip
          ips << ip
        end
        return ips
      end

      def destroy_static_ip(ip)
        address = @compute_provider.addresses.get(ip)
        return address.destroy
      end

      def create_image(image_name)
        raise NotImplementedError, "create_image not implemented in generic fog adapter"
      end

      def describe_images(image_id=nil)
        images = []
        opts = {"Owner" => "self"}
        opts["image-id"] = image_id if image_id
        response = @compute_provider.images.all(opts)
        response.each do |item|
          image = {}
          image[:id] = item.id
          image[:location] = item.location
          image[:root_device_type] = item.root_device_type
          images << image
        end
        return images
      end

      def destroy_image(image_id)
        raise NotImplementedError, "destroy_image not implemented in generic fog adapter"
      end

      def describe_load_balancers(name=nil)
        raise NotImplementedError, "describe_load_balancers not implemented in generic fog adapter"
      end

      def active_state
        raise NotImplementedError, "active_state not implemented in generic fog adapter"
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

      def isolate_prefix
        "#{env.app_name}_#{Rubber.env}_"
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

    end

  end
end
