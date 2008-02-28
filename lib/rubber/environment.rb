require 'yaml'
require 'socket'

module Rubber
  module Configuration
    # Contains the configuration defined in rubber.yml
    # Handles selecting of correct config values based on
    # the host/role passed into bind
    class Environment
      attr_reader :file

      def initialize(file)
        LOGGER.info{"Reading rubber configuration from #{file}"}
        @file = file
        @items = {}
        if File.exist?(@file)
          expanded = eval('%Q{' + File.read(@file) + '}', binding, @file, 1)
          @items = YAML.load(expanded) || {}
        end
      end

      def known_roles
        roles_dir = File.join(File.dirname(@file), "role")
        roles = Dir.entries(roles_dir)
        roles.delete_if {|d| d =~ /(^\..*)/}
      end

      def current_host
        Socket::gethostname.gsub(/\..*/, '')
      end

      def bind(roles, host)
        BoundEnv.new(@items, roles, host)
      end

      class BoundEnv
        attr_reader :roles
        attr_reader :host

        def initialize(cfg, roles, host)
          @cfg = cfg
          @roles = roles
          @host = host
        end

        # combine old and new into a single value:
        # non-nil wins if other is nil
        # arrays just get unioned
        # hashes also get unioned, but the values of conflicting keys get combined
        # All else, the new value wins
        def combine(old, new)
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

        # get the environment value for the given key
        # if combine is true, value are cmobined for role/host overrides
        # if combine is false, host overrides roles overrides global
        def get(name, combine=false)
          if combine
            value = @cfg[name]
            @roles.to_a.each do |role|
              value = combine(value, (@cfg["roles"][role][name] rescue nil))
            end
            value = combine(value, (@cfg["hosts"][@host][name] rescue nil))
          else
            value = @cfg[name]
            @roles.to_a.each do |role|
              v = @cfg["roles"][role][name] rescue nil
              value = v if v
            end
            v = @cfg["hosts"][@host][name] rescue nil
            value = v if v
          end
          return value
        end

        def [](name)
          get(name, true)
        end

        def method_missing(method_id)
          key = method_id.id2name
          self[key]
        end
      end

    end

  end
end