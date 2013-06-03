require 'rubber/cloud/generic'

module Rubber
  module Cloud
    class Vagrant < Generic

      def before_create_instance(instance_alias, role_names)
        unless ENV.has_key?('RUN_FROM_VAGRANT')
          $stderr.puts "Since you are using the 'vagrant' provider, you must create instances by running `vagrant up`."
          exit(-1)
        end
      end

      def destroy_instance(instance_id)
        system("vagrant destroy")
      end

    end
  end
end