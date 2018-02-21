require 'rubber/configuration/configuration_storage'

module Rubber
  module Configuration
    class S3ConfigurationStorage < ConfigurationStorage
      include MonitorMixin

      attr_reader :bucket, :key

      def initialize(cluster, path)
        super cluster, path

        @bucket = path.split("/")[0]
        @key = path.split("/")[1..-1].join("/")
      end

      def load
        data = Rubber.cloud.storage(bucket).fetch(key)

        StringIO.open(data, 'r') {|f| load_from_io(f) } if data
      end

      def save
        synchronize do
          data = StringIO.open {|f| save_to_io(f); f.string }

          Rubber.cloud.storage(bucket).store(key, data)
        end
      end
    end
  end
end
