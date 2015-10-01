require "rubber/cloud/base"

module Rubber
  module Cloud

    def self.get_provider(provider, env, capistrano)
      require "rubber/cloud/#{provider}"
      provider_env = env.cloud_providers[provider]

      if provider_env.vpc
        require "rubber/cloud/aws_vpc"
        clazz = Rubber::Cloud::AwsVpc
      else
        clazz = Rubber::Cloud.const_get(Rubber::Util.camelcase(provider))
      end

      return clazz.new(provider_env, capistrano)
    end

  end
end
