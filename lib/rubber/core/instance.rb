module Rubber
  module Core
    class Instance
      def self.cloud_provider
        Rubber.cloud
      end

      def cloud_provider
        self.class.cloud_provider
      end

      UBUNTU_OS_VERSION_CMD = 'lsb_release -sr'.freeze
      VARIABLES_TO_OMIT_IN_SERIALIZATION = %w[
        @capistrano @os_version @subnet_id @vpc_id @vpc_cidr
      ].freeze

      attr_reader :name, :domain, :instance_id, :image_type, :image_id, :security_groups

      attr_accessor :roles, :zone
      attr_accessor :external_host, :external_ip
      attr_accessor :internal_host, :internal_ip
      attr_accessor :static_ip, :volumes, :partitions, :root_device_type
      attr_accessor :spot_instance_request_id
      attr_accessor :provider, :platform
      attr_accessor :capistrano
      attr_accessor :vpc_id
      attr_accessor :network # more generic term for vpc_alias
      attr_accessor :vpc_cidr
      attr_accessor :subnet_id
      attr_accessor :gateway

      # Yielded by the Instance initializer, providers a sort of builder pattern
      # for some syntactic sugar instead of calling initializer with 6 parameters
      class Builder
        attr_accessor :name, :domain, :instance_id, :image_type, :image_id, :security_groups
      end

      def initialize
        @os_version = nil

        if block_given?
          builder = Builder.new

          yield builder

          @name = builder.name
          @domain = builder.domain
          @roles = builder.roles
          @instance_id = builder.instance_id
          @image_type = builder.image_type
          @image_id = builder.image_id
          @security_groups = builder.security_group_list
        end
      end

      def self.from_hash(hash)
        item = allocate
        hash.each do |k, v|
          sym = "@#{k}".to_sym
          v = v.collect {|r| RoleItem.parse(r) } if k == 'roles'
          item.instance_variable_set(sym, v)
        end
        return item
      end

      def to_hash
        hash = {}
        instance_variables.each do |iv|
          next if VARIABLES_TO_OMIT_IN_SERIALIZATION.include?(iv.to_s)

          name = iv.to_s.gsub(/^@/, '')
          value = instance_variable_get(iv)
          value = value.collect {|r| r.to_s } if name == 'roles'
          hash[name] = value
        end

        return hash
      end

      def <=>(rhs)
        name <=> rhs.name
      end

      def full_name
        "#{@name}.#{@domain}"
      end

      def role_names
        roles.map &:name
      end

      def provider
        # Deal with old instance configurations that don't have a provider value persisted.
        @provider || 'aws'
      end

      def platform
        # Deal with old instance configurations that don't have a platform value persisted.
        @platform || Rubber::Platforms::LINUX
      end

      def linux?
        platform == Rubber::Platforms::LINUX
      end

      def mac?
        platform == Rubber::Platforms::MAC
      end

      def windows?
        platform == Rubber::Platforms::WINDOWS
      end

      def os_version
        @os_version ||= begin
          os_version_cmd = Rubber.config.os_version_cmd || UBUNTU_OS_VERSION_CMD

          if capistrano
            @os_version = capistrano.capture(os_version_cmd, :host => self.full_name).chomp
          else
            # If we can't SSH to the machine, we may be able to execute the command locally if this
            # instance item happens to refer to the same machine we're executing on.
            if Socket::gethostname == self.full_name
              @os_version = `#{os_version_cmd}`.chomp
            else
              raise "Unable to get os_version for #{self.full_name}"
            end
          end
        end
      end

      def encode_with(coder)
        vars = instance_variables.map { |x| x.to_s }
        vars = vars - VARIABLES_TO_OMIT_IN_SERIALIZATION

        vars.each do |var|
          coder[var.gsub('@', '')] = eval(var)
        end
      end

      def create(verbose: true, spot_instance: false)
        # TODO this should all be passed in by the caller
        #      or in initialize
        availability_zone = cloud_env.availability_zone
        security_groups = get_assigned_security_groups(instance_alias, roles)

        ami = cloud_env.image_id
        ami_type = cloud_env.image_type
        region = cloud_env.region
        fog_options = cloud_env.fog_options || {}
        #################################################

        monitor.synchronize do
          cloud_provider.before_create_instance(self)
        end

        create_spot_instance if spot_instance

        # If spot_instance is false, or spot instance creation failed, this
        # should be true
        if instance_id.nil?
          if verbose
            sg_str = security_groups.join(',') rescue 'Default'
            az_str = availability_zone || region || 'Default'
            vpc_str = vpc_id || 'No VPC'

            logger.info "Creating instance #{ami}/#{ami_type}/#{sg_str}/#{az_str}/#{vpc_str}"
          end

          if vpc_id
            fog_options[:vpc_id] = vpc_id
            fog_options[:subnet_id] = subnet_id
            fog_options[:associate_public_ip] = (gateway == 'public')
          end
        end

        # Security Groups are handled in the after_create_instance callback of the
        # Vpc cloud provider, so pass an empty array here to make sure it isn't
        # assigned to any other default groups that might be floating around.
        @instance_id = cloud_provider.create_instance(
          instance_alias,
          ami,
          ami_type,
          fog_options[:vpc_id] ? security_groups : [],
          availability_zone,
          region,
          fog_options
        )
      end

      def create_spot_instance(verbose: true)
        spot_price = cloud_env.spot_price.to_s

        if verbose
          logger.info "Creating spot instance request for instance #{ami}/#{ami_type}/#{security_groups.join(',') rescue 'Default'}/#{availability_zone || 'Default'}"
        end

        request_id = cloud_provider.create_spot_instance_request(spot_price, ami, ami_type, security_groups, availability_zone, fog_options)

        print "Waiting for spot instance request to be fulfilled" if verbose

        @instance_id = nil

        max_wait_time = cloud_env.spot_instance_request_timeout || (1.0 / 0) # Use the specified timeout value or default to infinite.

        loop do
          print "." if verbose

          sleep 2
          max_wait_time -= 2

          request = cloud_provider.describe_spot_instance_requests(request_id).first
          @instance_id = request[:instance_id]

          if @instance_id
            @spot_instance_request_id = request_id

            break
          end

          if max_wait_time < 0 && instance_id.nil?
            cloud_provider.destroy_spot_instance_request(request[:id])

            if verbose
              print "\n"
              print "Failed to fulfill spot instance in the time specified. Falling back to on-demand instance creation."
            end

            break
          end
        end

        print "\n" if verbose

        return request_id if @instance_id
      end

      def start
      end

      def stop
      end

      def reboot
      end

      def refresh
      end

      def destroy
      end

      private

      def cloud_env
        return @cloud_env if defined? @cloud_env

        env = rubber_cfg.environment.bind(roles, instance_alias)
        @cloud_env = env.cloud_providers[env.cloud_provider]
      end
    end
  end
end
