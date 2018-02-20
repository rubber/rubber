module Rubber
  module Configuration
    class ConfigurationStorage
      attr_reader :cluster, :path

      def self.for_cluster_from_storage_string(cluster, storage_string)
        require 'rubber/configuration/file_configuration_storage'
        require 'rubber/configuration/s3_configuration_storage'
        require 'rubber/configuration/table_configuration_storage'

        case storage_string
        when /file:(.*)/
          FileConfigurationStorage.new(cluster, $1)
        when /storage:(.*)/
          S3ConfigurationStorage.new(cluster, $1)
        when /table:(.*)/
          TableConfigurationStorage.new(cluster, $1)
        else
          raise "Invalid configuration_storage string: #{storage_string}\n" +
                "Must be one of file:, table:, storage:"
        end
      end

      def initialize(cluster, path)
        @cluster = cluster
        @path = path
      end

      private

      def load_from_io(io)
        item_list = YAML.load(io.read)

        if item_list
          item_list.each do |i|
            if i.is_a? InstanceItem
              cluster.items[i.name] = i
            elsif i.is_a? Hash
              cluster.artifacts.merge!(i)
            end
          end
        end
      end

      def save_to_io(io)
        data = []
        data.push(*cluster.items.values)
        data.push(cluster.artifacts)
        io.write(YAML.dump(data))
      end
    end
  end
end
