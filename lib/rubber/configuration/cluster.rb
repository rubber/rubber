require 'rubber/configuration/instance_item'
require 'rubber/configuration/configuration_storage'

module Rubber
  module Configuration

    # Contains the ec2 cluster configuration defined in instance.yml
    #
    class Cluster
      attr_reader :configuration_storage, :artifacts, :items

      include Enumerable

      def initialize(configuration_storage_uri, opts={})
        @opts = opts

        @configuration_storage =
          ConfigurationStorage.for_cluster_from_storage_string(self,
                                                               configuration_storage_uri)

        if @opts[:backup]
          @backup_configuration_storage =
            ConfigurationStorage.for_cluster_from_storage_string(self,
                                                                 @opts[:backup])
        end

        @items = {}
        @artifacts = {'volumes' => {}, 'static_ips' => {}, 'vpc' => {}}

        @filters = Rubber::Util::parse_aliases(ENV['FILTER'])
        @filters, @filters_negated = @filters.partition {|f| f !~ /^-/ }
        @filters_negated = @filters_negated.collect {|f| f[1..-1] }

        @filter_roles = Rubber::Util::parse_aliases(ENV['FILTER_ROLES'])
        @filter_roles, @filter_roles_negated = @filter_roles.partition {|f| f !~ /^-/ }
        @filter_roles_negated = @filter_roles_negated.collect {|f| f[1..-1] }

        load
      end

      def load
        @configuration_storage.load
      end

      def save
        @configuration_storage.save
        @backup_configuration_storage.save if @backup_configuration_storage
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
