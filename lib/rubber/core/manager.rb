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

        # Security Groups are handled in the after_create_instance callback of the
        # Vpc cloud provider, so pass an empty array here to make sure it isn't
        # assigned to any other default groups that might be floating around.
        instance_id = cloud.create_instance(
          instance_alias,
          ami,
          ami_type,
          fog_options[:vpc_id] ? security_groups : [],
          availability_zone,
          region,
          fog_options
        )

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

        monitor.synchronize do
          cloud.after_create_instance(created_instance_item)
        end
      end

      def configuration
        @configuration ||= Configuration.new
      end

    end
  end
end
