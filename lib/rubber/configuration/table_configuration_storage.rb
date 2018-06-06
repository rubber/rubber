require 'rubber/configuration/configuration_storage'

module Rubber
  module Configuration
    class TableConfigurationStorage < ConfigurationStorage
      include MonitorMixin

      alias_method :table_key, :path

      def load
        Rubber.logger.debug{"Reading rubber instances from cloud table #{table_key}"}

        items = store.find()

        items.each do |name, data|
          case name
          when '_artifacts_'
            cluster.artifacts.replace(data)
          else
            ic = Server.from_hash(data.merge({'name' => name}))

            cluster.items[ic.name] = ic
          end
        end
      end

      def save
        synchronize do
          # delete all before writing to handle removals
          store.find().each do |k, v|
            store.delete(k)
          end

          # only write out non-empty artifacts
          artifacts = cluster.artifacts.select {|k, v| v.size > 0}
          if artifacts.size > 0
            store.put('_artifacts_', artifacts)
          end

          # write out all the instance data
          cluster.items.values.each do |item|
            store.put(item.name, item.to_hash)
          end
        end
      end

      private

      def store
        @store ||= Rubber.cloud.table_store(table_key)
      end
    end
  end
end
