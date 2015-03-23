require "rubber/cloud/base"

module Rubber
  module Cloud

    def self.get_provider(provider, env, capistrano)
      require "rubber/cloud/#{provider}"
      clazz = Rubber::Cloud.const_get(Rubber::Util.camelcase(provider))
      provider_env = env.cloud_providers[provider]
      return clazz.new(provider_env, capistrano)
    end

  end
end
