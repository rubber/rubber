require 'yaml'
require 'socket'

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
        @config_files = ["#{@config_root}/rubber.yml"] + Dir["#{@config_root}/rubber-*.yml"].sort
        @items = {}
        @config_files.each { |file| read_config(file) }
        @config_secret = bind().rubber_secret
        read_config(@config_secret) if @config_secret
      end
      
      def read_config(file)
        LOGGER.debug{"Reading rubber configuration from #{file}"}
        if File.exist?(file)
          @items = Environment.combine(@items, YAML.load_file(file) || {})
        end
      end

      def known_roles
        roles_dir = File.join(@config_root, "role")
        roles = Dir.entries(roles_dir)
        roles.delete_if {|d| d =~ /(^\..*)/}
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

      class BoundEnv
        attr_reader :roles
        attr_reader :host
        attr_reader :full_host

        def initialize(cfg, roles, host)
          @cfg = cfg
          @roles = roles
          @host = host
          @full_host = host + "." + self['domain'] rescue nil
        end

        # get the environment value for the given key
        # if combine is true, value are cmobined for role/host overrides
        # if combine is false, host overrides roles overrides global
        def get(name, combine=false, expand=false)
          if combine
            value = @cfg[name]
            @roles.to_a.each do |role|
              value = Environment.combine(value, (@cfg["roles"][role][name] rescue nil))
            end
            value = Environment.combine(value, (@cfg["hosts"][@host][name] rescue nil))
          else
            value = @cfg[name]
            @roles.to_a.each do |role|
              v = @cfg["roles"][role][name] rescue nil
              value = v if v
            end
            v = @cfg["hosts"][@host][name] rescue nil
            value = v if v
          end
          
          return (expand ? self.expand(value) : value)
        end

        def [](name)
          get(name, true, true)
        end

        def expand(val)
          case val
          when Hash
            val.inject({}) {|h, a| h[a[0]] = expand(a[1]); h}
          when String
            while val =~ /\#\{[^\}]+\}/
              val = eval('%Q{' + val + '}', binding)
            end
            val = true if val =="true"
            val = false if val == "false"
            val
          when Enumerable
            val.collect {|v| expand(v)}
          else
            val
          end
        end

        def method_missing(method_id)
          key = method_id.id2name
          self[key]
        end
      end

    end

  end
end