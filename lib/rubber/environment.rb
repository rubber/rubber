require 'yaml'
require 'socket'
require 'delegate'
require 'monitor'
require 'rubber/encryption'


module Rubber
  module Configuration
    # Contains the configuration defined in rubber.yml
    # Handles selecting of correct config values based on
    # the host/role passed into bind
    class Environment
      attr_reader :config_root
      attr_reader :config_env
      attr_reader :config_files
      attr_reader :config_secret

      def initialize(config_root, env)
        @config_root = config_root
        @config_env = env
        
        @config_files = ["#{@config_root}/rubber.yml"]
        @config_files += Dir["#{@config_root}/rubber-*.yml"].sort

        # add a config file for current env only so that you can override
        #things for specific envs
        @config_files -= Dir["#{@config_root}/rubber-*-env.yml"]
        env_yml = "#{@config_root}/rubber-#{Rubber.env}-env.yml"
        @config_files << env_yml if File.exist?(env_yml)
        
        @items = {}
        @config_files.each { |file| read_config(file) }

        read_secret_config
      end
      
      def read_config(file)
        Rubber.logger.debug{"Reading rubber configuration from #{file}"}
        if File.exist?(file)
          begin
            data = IO.read(file)
            data = yield(data) if block_given?
            @items = Environment.combine(@items, YAML::load(ERB.new(data).result) || {})
          rescue Exception => e
            Rubber.logger.error{"Unable to read rubber configuration from #{file}"}
            raise
          end
        end
      end

      def read_secret_config
        bound = bind()
        @config_secret = bound.rubber_secret
        if @config_secret
          obfuscation_key = bound.rubber_secret_key
          if obfuscation_key
            read_config(@config_secret) do |data|
              Rubber::Encryption.decrypt(data, obfuscation_key)
            end
          else
            read_config(@config_secret)
          end
        end
      end
      
      def known_roles
        return @known_roles if @known_roles
        
        roles = []
        # all the roles known about in config directory
        roles.concat Dir["#{@config_root}/role/*"].collect {|f| File.basename(f) }
        
        # all the roles known about in script directory
        roles.concat Dir["#{Rubber.root}/script/*/role/*"].collect {|f| File.basename(f) }
        
        # all the roles known about in yml files
        Dir["#{@config_root}/rubber*.yml"].each do |yml|
          rubber_yml = YAML::load(ERB.new(IO.read(yml)).result) rescue {}
          roles.concat(rubber_yml['roles'].keys) rescue nil
          roles.concat(rubber_yml['role_dependencies'].keys) rescue nil
          roles.concat(rubber_yml['role_dependencies'].values) rescue nil
        end
        
        @known_roles = roles.flatten.uniq.sort
      end
      
      def current_host
        Socket::gethostname.gsub(/\..*/, '')
      end
      
      def current_full_host
        Socket::gethostname
      end
      
      def bind(roles = nil, host = nil)
        BoundEnv.new(@items, roles, host, config_env)
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
            if nk.to_s[0..0] == '^'
              nk = nk[1..-1]
              value[nk] = combine(nil, nv)
            else
              value[nk] = combine(value[nk], nv)
            end
          end
        elsif old.is_a?(Array) && new.is_a?(Array)
          value = old | new
        else
          value = new
        end

        value
      end

      class HashValueProxy < Hash
        include MonitorMixin

        attr_reader :global, :cache

        def initialize(global, receiver)
          @global = global
          @cache = {}
          super()
          replace(receiver)
        end

        def rubber_instances
          Rubber.instances
        end

        def known_roles
          Rubber::Configuration.get_configuration(Rubber.env).environment.known_roles
        end

        def [](name)
          unless cache.has_key?(name)
            synchronize do
              value = super(name)
              value = global[name] if global && !value
              cache[name] = expand(value)
            end
          end

          cache[name]
        end

        def each
          each_key do |key|
            yield key, self[key]
          end
        end
        
        # allows expansion when to_a gets called on hash proxy, e.g. when wrapping
        # a var in Array() to ensure error free iteration for possible null values
        def to_a
          self.collect {|k, v| [k, v]}
        end

        def method_missing(method_id)
          self[method_id.id2name]
        end

        def expand_string(val)
          while val =~ /\#\{[^\}]+\}/
            val = eval('%Q{' + val + '}', binding, __FILE__)
          end

          val = true if val =="true"
          val = false if val == "false"

          val
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

          val
        end

      end

      class BoundEnv < HashValueProxy
        attr_reader :roles
        attr_reader :host
        attr_reader :env

        def initialize(global, roles, host, env)
          @roles = roles
          @host = host
          @env = env
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
          env_overrides = global.delete("environments") || {}
          host_overrides = global.delete("hosts") || {}

          Array(roles).each do |role|
            Array(role_overrides[role]).each do |k, v|
              global[k] = Environment.combine(global[k], v)
            end
          end

          Array(env_overrides[env]).each do |k, v|
            global[k] = Environment.combine(global[k], v)
          end

          Array(host_overrides[host]).each do |k, v|
            global[k] = Environment.combine(global[k], v)
          end

          global
        end
        
        def method_missing(method_id)
          self[method_id.id2name]
        end

      end

    end

  end
end
