require 'resolv-replace'
require 'singleton'

module Rubber
  class Resolver < Resolv::Hosts

    include Singleton

    def initialize
      @filename = 'Rubber'
      @mutex = Mutex.new
      clear_cache
    end

    def lazy_initialize
      @mutex.synchronize do
        unless @initialized
          ip_method = running_in_cluster? ? :internal_ip : :external_ip

          ::Rubber.instances.each do |ic|
            aliases = []

            if ic.role_names.include?('web_tools')
              Array(::Rubber.config.web_tools_proxies).each do |name, settings|
                aliases << "#{name.gsub('_', '-')}-#{ic.full_name}"
              end
            end

            ip_address = ic.send(ip_method)
            @addr2name[ip_address] = [ic.full_name] + aliases
            @name2addr[ic.full_name] = [ip_address]
            aliases.each { |name| @name2addr[name] = [ip_address] }
          end

          @initialized = true
        end
      end
      
      self
    end

    private

    def running_in_cluster?
      ! ::Rubber.instances[Socket::gethostname].nil?
    end

    def clear_cache
      @mutex.synchronize do
        @initialized = nil
        @name2addr = {}
        @addr2name = {}
      end
    end
  end

end

resolvers = Resolv::DefaultResolver.instance_variable_get(:@resolvers)
Resolv::DefaultResolver.replace_resolvers([::Rubber::Resolver.instance] + resolvers)