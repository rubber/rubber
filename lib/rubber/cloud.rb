require "rubber/cloud/base"

module Rubber
  module Cloud

    def self.get_provider(provider, env, capistrano)
      require "rubber/cloud/#{provider}"
      provider_env = env.cloud_providers[provider]

      # Check to see if we have a Rubber::Cloud::Provider::Factory class.  If
      # not, fall back to Rubber::Cloud::Provider
      begin
        factory = Rubber::Cloud.const_get(Rubber::Util.camelcase(provider))::Factory
        return factory.get_provider(provider_env, capistrano)
      rescue NameError => e
        clazz = Rubber::Cloud.const_get(Rubber::Util.camelcase(provider))
        return clazz.new(provider_env, capistrano)
      end
    end

  end
end

