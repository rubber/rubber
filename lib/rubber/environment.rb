require 'yaml'
require 'socket'
require 'delegate'

module Rubber
  module Configuration
    # Contains the configuration defined in rubber.yml
    # Handles selecting of correct config values based on
    # the host/role passed into bind
    class Environment
      attr_reader :config_root
      attr_reader :config_files
      attr_reader :config_secret

      def initialize(config_root)
        @config_root = config_root
        @config_files = ["#{@config_root}/rubber.yml"]
        @config_files += Dir["#{@config_root}/rubber-*.yml"].sort

        # add a config file for current env only so that you can override
        #things for specific envs
        @config_files -= Dir["#{@config_root}/rubber-*-env.yml"]
        env_yml = "#{@config_root}/rubber-#{Rubber.env}-env.yml"
        @config_files << env_yml if File.exist?(env_yml)
        
        @items = {}
        @config_files.each { |file| read_config(file) }
        @config_secret = bind().rubber_secret
        read_config(@config_secret) if @config_secret
      end
      
      def read_config(file)
        Rubber.logger.debug{"Reading rubber configuration from #{file}"}
        if File.exist?(file)
          begin
            @items = Environment.combine(@items, YAML.load_file(file) || {})
          rescue Exception => e
            Rubber.logger.error{"Unable to read rubber configuration from #{file}"}
            raise
          end
        end
      end

      def known_roles
        roles_dir = File.join(@config_root, "role")
        roles = Dir.entries(roles_dir)
        roles.delete_if {|d| d =~ /(^\..*)/}
        roles += @items['roles'].keys
        return roles.compact.uniq
      end

      def current_host
        Socket::gethostname.gsub(/\..*/, '')
      end
      
      def current_full_host
        Socket::gethostname
      end
      
      def bind(roles = nil, host = nil)
        BoundEnv.new(@items, roles, host)
      end

      # combine old and new into a single value:
      # non-nil wins if other is nil
      # arrays just get unioned
      # hashes also get unioned, but the values of conflicting keys get combined
      # All else, the new value wins
      def self.combine(old, new)
        return old if new.nil?
        return new if old.nil?
        value = old
        if old.is_a?(Hash) && new.is_a?(Hash)
          value = old.clone
          new.each do |nk, nv|
            value[nk] = combine(value[nk], nv)
          end
        elsif old.is_a?(Array) && new.is_a?(Array)
          value = old | new
        else
          value = new
        end
        return value
      end

      class HashValueProxy < Hash
        attr_reader :global

        def initialize(global, receiver)
          @global = global
          super()
          replace(receiver)
        end

        def rubber_instances
          @rubber_instances ||= Rubber::Configuration::rubber_instances
        end

        def [](name)
          value = super(name)
          value = global[name] if global && !value
          return expand(value)
        end

        def each
          each_key do |key|
            yield key, self[key]
          end
        end

        def method_missing(method_id)
          key = method_id.id2name
          return self[key]
        end

        def expand_string(val)
          while val =~ /\#\{[^\}]+\}/
            val = eval('%Q{' + val + '}', binding)
          end
          val = true if val =="true"
          val = false if val == "false"
          return val
        end

        def expand(value)
          val = case value
            when Hash
              HashValueProxy.new(global || self, value)
            when String
              expand_string(value)
            when Enumerable
              value.collect {|v| expand(v) }
            else
              value
          end
          return val
        end

      end

      class BoundEnv < HashValueProxy
        attr_reader :roles
        attr_reader :host

        def initialize(global, roles, host)
          @roles = roles
          @host = host
          bound_global = bind_config(global)
          super(nil, bound_global)
        end

        def full_host
          @full_host ||= "#{host}.#{domain}" rescue nil
        end

        # Forces role/host overrides into config
        def bind_config(global)
          global = global.clone()
          role_overrides = global.delete("roles") || {}
          host_overrides = global.delete("hosts") || {}
          Array(roles).each do |role|
            Array(role_overrides[role]).each do |k, v|
              global[k] = Environment.combine(global[k], v)
            end
          end
          Array(host_overrides[host]).each do |k, v|
            global[k] = Environment.combine(global[k], v)
          end
          return global
        end
        
        def method_missing(method_id)
          key = method_id.id2name
          return self[key]
        end

      end

    end

  end
end