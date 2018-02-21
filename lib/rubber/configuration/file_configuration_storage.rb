require 'rubber/configuration/configuration_storage'

module Rubber
  module Configuration
    class FileConfigurationStorage < ConfigurationStorage
      include MonitorMixin

      def load
        File.open(path, 'r') { |f| load_from_io(f) } if File.exist?(path)
      end

      def save
        synchronize do
          File.open(path, 'w') { |f| save_to_io(f) }
        end
      end
    end
  end
end
