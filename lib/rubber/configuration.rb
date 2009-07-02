require 'logger'
require 'rubber/environment'
require 'rubber/instance'
require 'rubber/generator'

module Rubber
  module Configuration

    @@configurations = {}

    def self.get_configuration(env=nil, root=nil)
      key = "#{env}-#{root}"
      @@configurations[key] ||= ConfigHolder.new(env, root)
    end

    def self.rubber_env
      raise "This convenience method needs RUBBER_ENV to be set" unless RUBBER_ENV
      cfg = Rubber::Configuration.get_configuration(RUBBER_ENV)
      host = cfg.environment.current_host
      roles = cfg.instance[host].role_names rescue nil
      cfg.environment.bind(roles, host)
    end

    def self.rubber_instances
      raise "This convenience method needs RUBBER_ENV to be set" unless RUBBER_ENV
      Rubber::Configuration.get_configuration(RUBBER_ENV).instance
    end

    class ConfigHolder
      def initialize(env=nil, root=nil)
        root = "#{RUBBER_ROOT}/config/rubber" unless root
        instance_cfg =  "#{root}/instance" + (env ? "-#{env}.yml" : ".yml")
        @environment = Environment.new("#{root}")
        @instance = Instance.new(instance_cfg)
      end

      def environment
        @environment
      end

      def instance
        @instance
      end
    end

  end
end
