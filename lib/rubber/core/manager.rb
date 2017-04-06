module Rubber
  module Core
    class Manager
      delegate [
        :aliases,
        :roles
      ] => :configuration

      def create_instances(aliases: aliases, roles: roles, spot_instance: false)
      end

      def create_instance(instance_alias: instance_alias, roles: roles)
        instance_item = Rubber::Configuration::InstanceItem.new(instance_alias, env.domain, instance_roles, nil, ami_type, ami, security_groups)

        instance_item.zone = availability_zone


        create_spot_instance ||= cloud_env.spot_instance

        if create_spot_instance
          spot_price = cloud_env.spot_price.to_s

          logger.info "Creating spot instance request for instance #{ami}/#{ami_type}/#{security_groups.join(',') rescue 'Default'}/#{availability_zone || 'Default'}"
          request_id = cloud.create_spot_instance_request(spot_price, ami, ami_type, security_groups, availability_zone, fog_options)

          print "Waiting for spot instance request to be fulfilled"
          max_wait_time = cloud_env.spot_instance_request_timeout || (1.0 / 0) # Use the specified timeout value or default to infinite.
          instance_id = nil
          while instance_id.nil? do
            print "."
            sleep 2
            max_wait_time -= 2

            request = cloud.describe_spot_instance_requests(request_id).first
            instance_id = request[:instance_id]

            if max_wait_time < 0 && instance_id.nil?
              cloud.destroy_spot_instance_request(request[:id])

              print "\n"
              print "Failed to fulfill spot instance in the time specified. Falling back to on-demand instance creation."
              break
            end
          end

          print "\n"
        end

        if !create_spot_instance || (create_spot_instance && max_wait_time < 0)
          sg_str = security_groups.join(',') rescue 'Default'
          az_str = availability_zone || region || 'Default'
          vpc_str = instance_item.vpc_id || 'No VPC'

          logger.info "Creating instance #{ami}/#{ami_type}/#{sg_str}/#{az_str}/#{vpc_str}"

          if instance_item.vpc_id
            fog_options[:vpc_id] = instance_item.vpc_id
            fog_options[:subnet_id] = instance_item.subnet_id
            fog_options[:associate_public_ip] = (instance_item.gateway == 'public')
          end
        end


        logger.info "Instance #{instance_alias} created: #{instance_id}"

        # Recreate the InstanceItem now that we have an instance_id
        created_instance_item = Rubber::Configuration::InstanceItem.new(
          instance_alias,
          env.domain,
          instance_roles,
          instance_id,
          ami_type,
          ami,
          security_groups
        )
        created_instance_item.vpc_id = instance_item.vpc_id
        created_instance_item.network = instance_item.network
        created_instance_item.spot_instance_request_id = request_id if create_spot_instance
        created_instance_item.capistrano = self
        created_instance_item.gateway = instance_item.gateway
        rubber_instances.add(created_instance_item)
        rubber_instances.save()
      end

      def configuration
        @configuration ||= Configuration.new
      end
    end
  end
end
