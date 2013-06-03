require 'rubber/cloud/generic'

module Rubber
  module Cloud
    class Vagrant < Generic

      def active_state
        'running'
      end

      def stopped_state
        'saved'
      end

      def before_create_instance(instance_alias, role_names)
        unless ENV.has_key?('RUN_FROM_VAGRANT')
          capistrano.fatal "Since you are using the 'vagrant' provider, you must create instances by running `vagrant up #{instance_alias}`."
        end
      end

      def describe_instances(instance_id=nil)
        output = `vagrant status #{instance_id}`

        output =~ /#{instance_id}\s+(\w+)/m
        state = $1

        if Vagrant.instances
          Vagrant.instances.each do |instance|
            if instance[:id] == instance_id
              instance[:state] = state
            end
          end

          Vagrant.instances
        else
          instance = {}
          instance[:id] = instance_id
          instance[:state] = state

          [instance]
        end
      end

      def destroy_instance(instance_id)
        system("vagrant destroy #{instance_id} --force")
      end

      def stop_instance(instance, force=false)
        system("vagrant suspend #{instance.instance_id}")
      end

      def start_instance(instance)
        system("vagrant resume #{instance.instance_id}")
      end
    end
  end
end