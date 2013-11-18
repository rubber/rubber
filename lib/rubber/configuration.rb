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
      roles = cfg.instance[host] ? cfg.instance[host].role_names : nil
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
        @environment = Environment.new("#{@root}", @env)
      end

      def load
        config = @environment.bind()
        instance_storage = config['instance_storage']
        instance_storage_backup = config['instance_storage_backup']
        instance_storage ||= "file:#{@root}/instance-#{@env}.yml"
        @instance = Instance.new(instance_storage, :backup => instance_storage_backup)
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
