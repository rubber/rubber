require 'logger'
require 'rubber/environment'
require 'rubber/configuration/cluster'
require 'rubber/generator'

module Rubber
  module Configuration
    extend MonitorMixin

    @@configurations = {}

    def self.get_configuration(env=nil, root=nil)
      key = "#{env}-#{root}"

      synchronize do
        unless @@configurations[key]
          @@configurations[key] = ConfigHolder.new(env, root)
          @@configurations[key].load()
        end
      end

      return @@configurations[key]
    end

    def self.rubber_env
      raise "This convenience method needs Rubber.env to be set" unless Rubber.env
      cfg = Rubber::Configuration.get_configuration(Rubber.env)
      host = cfg.environment.current_host
      roles = cfg.cluster[host] ? cfg.cluster[host].role_names : nil
      cfg.environment.bind(roles, host)
    end

    def self.rubber_cluster
      raise "This convenience method needs Rubber.env to be set" unless Rubber.env
      Rubber::Configuration.get_configuration(Rubber.env).cluster
    end

    # Despite the name changes of Instance -> Cluster, and InstanceItem -> Server,
    # keeping an accessor called instances still feels appropriate.  Instance is a
    # more generic, base type for a Server which could also be use to describe
    # non-server pieces of the cluster (ELB/Digital Ocean load balancers, AWS
    # Aurora Serverless instances, etc
    def self.rubber_instances
      rubber_cluster
    end

    def self.reset
      synchronize do
        @@configurations.clear
      end
    end

    class ConfigHolder
      def initialize(env=nil, root=nil)
        @env = env
        @root = root || "#{Rubber.root}/config/rubber"
        @environment = Environment.new("#{@root}", @env)
      end

      def load
        config = @environment.bind()
        cluster_storage = config['configuration_storage'] || config['instance_storage']
        cluster_storage_backup = config['configuration_storage_backup'] || config['instance_storage_backup']

        unless cluster_storage
          if File.exists? legacy_cluster_file_path
            cluster_storage = "file:#{legacy_cluster_file_path}"
          else
            cluster_storage = "file:#{cluster_file_path}"
          end
        end

        @cluster = Cluster.new(cluster_storage, backup: cluster_storage_backup)
      end

      def environment
        @environment
      end

      def cluster
        @cluster
      end

      def cluster_file_path
        "#{@root}/cluster-#{@env}.yml"
      end

      def legacy_cluster_file_path
        "#{@root}/instance-#{@env}.yml"
      end
    end
  end
end
