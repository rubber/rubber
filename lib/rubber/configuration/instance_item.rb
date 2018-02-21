require 'rubber/configuration/role_item'

module Rubber
  module Configuration
    # The configuration for a single instance
    class InstanceItem
      UBUNTU_OS_VERSION_CMD = 'lsb_release -sr'.freeze
      VARIABLES_TO_OMIT_IN_SERIALIZATION = [
        '@capistrano', '@os_version', '@subnet_id', '@vpc_id',
        '@vpc_cidr'
      ]

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

      def initialize(name, domain, roles, instance_id, image_type, image_id, security_group_list=[])
        @name = name
        @domain = domain
        @roles = roles
        @instance_id = instance_id
        @image_type = image_type
        @image_id = image_id
        @security_groups = security_group_list
        @os_version = nil
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
        roles.collect {|r| r.name}
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
    end
  end
end
