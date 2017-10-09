require 'rubber/configuration/instance_item'

module Rubber
  module Configuration

    # Contains the ec2 cluster configuration defined in instance.yml
    #
    class Cluster
      attr_reader :configuration_storage, :artifacts
      include Enumerable
      include MonitorMixin

      def initialize(configuration_storage, opts={})
        super()

        @configuration_storage = configuration_storage
        @opts = opts

        @items = {}
        @artifacts = {'volumes' => {}, 'static_ips' => {}, 'vpc' => {}}

        @filters = Rubber::Util::parse_aliases(ENV['FILTER'])
        @filters, @filters_negated = @filters.partition {|f| f !~ /^-/ }
        @filters_negated = @filters_negated.collect {|f| f[1..-1] }

        @filter_roles = Rubber::Util::parse_aliases(ENV['FILTER_ROLES'])
        @filter_roles, @filter_roles_negated = @filter_roles.partition {|f| f !~ /^-/ }
        @filter_roles_negated = @filter_roles_negated.collect {|f| f[1..-1] }

        load()
      end

      def load(configuration_storage=@configuration_storage)
        case configuration_storage
          when /file:(.*)/
            location = $1
            File.open(location, 'r') {|f| load_from_file(f) } if File.exist?(location)
          when /storage:(.*)/
            location = $1
            bucket = location.split("/")[0]
            key = location.split("/")[1..-1].join("/")
            data = Rubber.cloud.storage(bucket).fetch(key)
            StringIO.open(data, 'r') {|f| load_from_file(f) } if data
          when /table:(.*)/
            location = $1
            load_from_table(location)
          else
            raise "Invalid configuration_storage: #{configuration_storage}\n" +
                "Must be one of file:, table:, storage:"
        end
      end

      def load_from_file(io)
        item_list = YAML.load(io.read)
        if item_list
          item_list.each do |i|
            if i.is_a? InstanceItem
              @items[i.name] = i
            elsif i.is_a? Hash
              @artifacts.merge!(i)
            end
          end
        end
      end

      def load_from_table(table_key)
        Rubber.logger.debug{"Reading rubber instances from cloud table #{table_key}"}
        store = Rubber.cloud.table_store(table_key)
        items = store.find()
        items.each do |name, data|
          case name
            when '_artifacts_'
              @artifacts = data
            else
              ic = InstanceItem.from_hash(data.merge({'name' => name}))
              @items[ic.name] = ic
          end
        end
      end

      def save(configuration_storage=@configuration_storage, backup=@opts[:backup])
        synchronize do
          case configuration_storage
            when /file:(.*)/
              location = $1
              File.open(location, 'w') {|f| save_to_file(f) }
            when /storage:(.*)/
              location = $1
              bucket = location.split("/")[0]
              key = location.split("/")[1..-1].join("/")
              data = StringIO.open {|f| save_to_file(f); f.string }
              Rubber.cloud.storage(bucket).store(key, data)
            when /table:(.*)/
              location = $1
              save_to_table(location)
            else
              raise "Invalid configuration_storage: #{configuration_storage}\n" +
                  "Must be one of file:, table:, storage:"
          end
        end

        save(backup, false) if backup
      end

      def save_to_file(io)
        data = []
        data.push(*@items.values)
        data.push(@artifacts)
        io.write(YAML.dump(data))
      end

      def save_to_table(table_key)
        store = Rubber.cloud.table_store(table_key)

        # delete all before writing to handle removals
        store.find().each do |k, v|
          store.delete(k)
        end

        # only write out non-empty artifacts
        artifacts = @artifacts.select {|k, v| v.size > 0}
        if artifacts.size > 0
          store.put('_artifacts_', artifacts)
        end

        # write out all the instance data
        @items.values.each do |item|
          store.put(item.name, item.to_hash)
        end
      end

      def [](name)
        @items[name] || @items[name.gsub(/\..*/, '')]
      end

      # gets the instances for the given role.  If options is nil, all roles
      # match, otherwise the role has to have options that match exactly
      def for_role(role_name, options=nil)
        @items.values.find_all {|ic| ic.roles.any? {|r| r.name == role_name && (! options || r.options == options)}}
      end

      def filtered
        filtered_results = []

        validate_filters()

        if @filters.size == 0 && @filter_roles.size == 0
          filtered_results.concat(@items.values)
        else
          @items.values.each do |ic|
              filtered_results << ic if @filters.include?(ic.name)
              filtered_results << ic if ic.roles.any? {|r| @filter_roles.include?(r.name)}
          end
        end

        filtered_results.delete_if {|ic| @filters_negated.include?(ic.name) }
        filtered_results.delete_if {|ic| ic.roles.any? {|r| @filter_roles_negated.include?(r.name)} }

        return filtered_results
      end

      def validate_filters
        aliases = @items.values.collect{|ic| ic.name}
        [@filters, @filters_negated].flatten.each do |f|
          raise "Filter doesn't match any hosts: #{f}" if ! aliases.include?(f)
        end

        roles = all_roles
        [@filter_roles, @filter_roles_negated].flatten.each do |f|
          raise "Filter doesn't match any roles: #{f}" if ! roles.include?(f)
        end
      end

      def all_roles
        @items.collect {|n, i| i.role_names}.flatten.uniq
      end

      def add(instance_item)
        @items[instance_item.name] = instance_item
      end

      def remove(name)
        @items.delete(name)
      end

      def each(&block)
        @items.values.each &block
      end

      def size
        @items.size
      end
    end
  end
end
