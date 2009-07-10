require "rubber/dns/base.rb"

module Rubber
  module Dns

    def self.get_provider(provider, env)
      require "rubber/dns/#{provider}"
      clazz = Rubber::Dns.const_get(provider.capitalize)
      return clazz.new(env)
    end
    
  end
end
