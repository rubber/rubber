require 'rubber/cloud/fog'

module Rubber
  module Cloud
    class Generic < Fog
      MUTEX = Mutex.new

      def initialize(env, capistrano)
        # TODO (nirvdrum 05/23/13): This is here until the storage provider stuff is cleaned up.  That's why this class inherits from Base rather than Fog.
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

        super(env, capistrano)
      end

      def active_state
        'active'
      end

      def create_instance(instance_alias, image_name, image_type, security_groups, availability_zone, region)
        instance = {}
        instance[:id] = instance_alias
        instance[:state] = active_state
        instance[:external_ip] = capistrano.rubber.get_env('EXTERNAL_IP', "External IP address for host '#{instance_alias}'", true)
        instance[:internal_ip] = capistrano.rubber.get_env('INTERNAL_IP', "Internal IP address for host '#{instance_alias}'", true, instance[:external_ip])
        instance[:provider] = 'generic'
        instance[:platform] = Rubber::Platforms::LINUX

        Generic.add_instance(instance)

        instance_alias
      end

      def describe_instances(instance_id=nil)
        # Since there's no API to query for instance details, the best we can do is use what we have in memory from
        # the :create_instance operation or ask the user for the details again.
        unless Generic.instances
          create_instance(instance_id, nil, nil, nil, nil, nil)
        end

        Generic.instances
      end

      def self.add_instance(instance)
        MUTEX.synchronize do
          @instances ||= []
          @instances << instance
        end
      end

      def self.instances
        MUTEX.synchronize do
          @instances
        end
      end
    end
  end
end