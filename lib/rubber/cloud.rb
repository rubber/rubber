require "rubber/cloud/base"

module Rubber
  module Cloud

    def self.get_provider(provider, env)
      require "rubber/cloud/#{provider}"
      clazz = Rubber::Cloud.const_get(provider.capitalize)
      return clazz.new(env)
    end

  end
end
