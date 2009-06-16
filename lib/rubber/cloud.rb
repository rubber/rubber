require "rubber/cloud/base"

module Rubber
  module Cloud

    def self.get_provider(provider, env, capistrano)
      require "rubber/cloud/#{provider}"
      clazz = Rubber::Cloud.const_get(provider.capitalize)
      return clazz.new(env, capistrano)
    end

  end
end
