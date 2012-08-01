require "rubber/dns/base.rb"

module Rubber
  module Dns

    def self.get_provider(provider, env)

      if provider == 'fog'
        # TODO: remove backwards compatibility in next major release
        
        provider_env = env.dns_providers['fog']
        puts "deprecated dns provider config: #{provider_env}"
        creds = provider_env.credentials
        real_provider = creds.provider
        require "rubber/dns/#{real_provider}"
        clazz = Rubber::Dns.const_get(real_provider.capitalize)
        case real_provider
          when 'aws'
            provider_env['access_key'] = creds['aws_access_key_id']
            provider_env['access_secret'] = creds['aws_secret_access_key']
          when 'zerigo'
            provider_env['email'] = creds['zerigo_email']
            provider_env['token'] = creds['zerigo_token']
        end
        return clazz.new(provider_env)
        
      else
        
        require "rubber/dns/#{provider}"
        clazz = Rubber::Dns.const_get(provider.capitalize)
        provider_env = env.dns_providers[provider]
        return clazz.new(provider_env)
        
      end
      
    end
    
  end
end
