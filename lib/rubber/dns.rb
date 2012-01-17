require "rubber/dns/base.rb"

module Rubber
  module Dns

    def self.get_provider(provider, env)
      require "rubber/dns/#{provider}"
      clazz = Rubber::Dns.const_get(provider.capitalize)
      provider_env = env.dns_providers[provider]
      return clazz.new(provider_env)
    end
    
  end
end
