require 'yaml'

module Rubber
  module Configuration

    # Contains the ec2 instance configuration defined in instance.yml
    #
    class Instance
      attr_reader :file
      include Enumerable

      def initialize(file)
        LOGGER.debug{"Reading rubber instances from #{file}"}
        @file = file
        @items = {}
        if ENV['FILTER']
          @filters = ENV['FILTER'].split(/\s*,\s*/)
        end

        if File.exist?(@file)
          item_list = File.open(@file) { |f| YAML.load(f) }
          if item_list
            item_list.each do |i|
              @items[i.name] = i
            end
          end
        end
      end

      def save()
          File.open(@file, "w") { |f| f.write(YAML.dump(@items.values)) }
      end

      def [](name)
        @items[name] || @items[name.gsub(/\..*/, '')]
      end

      # gets the instances for the given role.  If options is nil, all roles
      # match, otherwise the role has to have options that match exactly
      def for_role(role_name, options=nil)
        @items.values.find_all {|ic| ic.roles.any? {|r| r.name == role_name && (! options || r.options == options)}}
      end

      def filtered()
        @items.values.find_all {|ic| ! @filters || @filters.include?(ic.name)}
      end

      def all_roles()
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

    # The configuration for a single instance
    class InstanceItem
      attr_reader :name, :domain, :roles, :instance_id
      attr_accessor :external_host, :external_ip
      attr_accessor :internal_host, :internal_ip
      attr_accessor :static_ip

      def initialize(name, domain, roles, instance_id)
        @name = name
        @domain = domain
        @roles = roles
        @instance_id = instance_id
      end

      def full_name
        "#@name.#@domain"
      end

      def role_names()
        roles.collect {|r| r.name}
      end
    end

    # The configuration for a single role contained in the list
    # of roles in InstanceItem
    class RoleItem
      attr_reader :name, :options

      def initialize(name, options={})
        @name = name
        @options = options
      end
    end

  end
end

