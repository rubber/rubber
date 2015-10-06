module Rubber
  module Cloud  
    module Aws

      class Factory
        def self.get_provider(provider_env, capistrano)
          require 'rubber/cloud/aws/vpc'
          require 'rubber/cloud/aws/classic'

          klazz = provider_env.vpc_alias ? Rubber::Cloud::Aws::Vpc : Rubber::Cloud::Aws::Classic
          klazz.new provider_env, capistrano
        end
      end

    end
  end
end

