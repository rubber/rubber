require 'logger'
require 'rubber/environment'
require 'rubber/instance'
require 'rubber/generator'

module Rubber
  module Configuration

    @@configurations = {}

    def self.get_configuration(env=nil, root=nil)
      key = "#{env}-#{root}"
      unless @@configurations[key]
        @@configurations[key] = ConfigHolder.new(env, root)
        @@configurations[key].load()
      end
      return @@configurations[key]
    end

    def self.rubber_env
      raise "This convenience method needs Rubber.env to be set" unless Rubber.env
      cfg = Rubber::Configuration.get_configuration(Rubber.env)
      host = cfg.environment.current_host
      roles = cfg.instance[host].role_names rescue nil
      cfg.environment.bind(roles, host)
    end

    def self.rubber_instances
      raise "This convenience method needs Rubber.env to be set" unless Rubber.env
      Rubber::Configuration.get_configuration(Rubber.env).instance
    end

    class ConfigHolder
      def initialize(env=nil, root=nil)
        @env = env
        @root = root || "#{Rubber.root}/config/rubber"
        @environment = Environment.new("#{@root}")
      end

      def load
        config = @environment.bind()
        is_cloud = config['instance_cloud_storage']
        if is_cloud
          key = "RubberInstances_#{config['app_name']}" +(@env ? "_#{@env}" : "")
          @instance = Instance.new(:cloud_key => key)
        else
          instance_cfg =  "#{@root}/instance" + (@env ? "-#{@env}.yml" : ".yml")
          @instance = Instance.new(:file => instance_cfg)
        end
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
