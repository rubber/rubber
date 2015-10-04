module Rubber
  module Cloud  
    module Aws

      class Factory
        def self.get_provider(provider_env, capistrano)
          if provider_env.vpc
            require 'rubber/cloud/aws/vpc'

            Rubber::Cloud::Aws::Vpc.new provider_env, capistrano
          else
            require 'rubber/cloud/aws/classic'

            Rubber::Cloud::Aws::Classic.new provider_env, capistrano
          end
        end
      end

    end
  end      
end

