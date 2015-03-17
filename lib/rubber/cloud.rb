require "rubber/cloud/base"
require 'pry'
module Rubber
  module Cloud

    def self.get_provider(provider, env, capistrano)
      binding.pry
      require "rubber/cloud/#{provider}"
      clazz = Rubber::Cloud.const_get(Rubber::Util.camelcase(provider))
      provider_env = env.cloud_providers[provider]
      return clazz.new(provider_env, capistrano)
    end

  end
end
