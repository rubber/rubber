require 'yaml'

module Rubber
  module Configuration

    # Contains the ec2 instance configuration defined in instance.yml
    #
    class Instance
      attr_reader :file, :artifacts
      include Enumerable

      def initialize(file)
        LOGGER.debug{"Reading rubber instances from #{file}"}
        @file = file
        @items = {}
        @artifacts = {'volumes' => {}, 'static_ips' => {}}
        if ENV['FILTER']
          @filters = ENV['FILTER'].split(/\s*,\s*/)
        end

        if File.exist?(@file)
          item_list = File.open(@file) { |f| YAML.load(f) }
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
      end

      def save()
        data = []
        data.push(*@items.values)
        data.push(@artifacts)
        File.open(@file, "w") { |f| f.write(YAML.dump(data)) }
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
      attr_reader :name, :domain, :instance_id, :security_groups
      attr_accessor :roles, :zone
      attr_accessor :external_host, :external_ip
      attr_accessor :internal_host, :internal_ip
      attr_accessor :static_ip, :volumes, :partitions
      attr_accessor :spot_instance_request_id

      def initialize(name, domain, roles, instance_id, security_group_list=[])
        @name = name
        @domain = domain
        @roles = roles
        @instance_id = instance_id
        @security_groups = security_group_list
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

      def self.expand_role_dependencies(roles, dependency_map, expanded=[])
        roles = Array(roles)
        roles.each do |role|
          unless expanded.include?(role)
            expanded << role
            needed = dependency_map[role]
            expand_role_dependencies(needed, dependency_map, expanded)
          end
        end
        return expanded
      end

      def self.parse(str)
        data = str.split(':');
        role = Rubber::Configuration::RoleItem.new(data[0])
        if data[1]
          data[1].split(';').each do |pair|
            p = pair.split('=')
            val = case p[1]
                    when 'true' then true
                    when 'false' then false
                    else p[1] end
            role.options[p[0]] = val
          end
        end
        return role
      end

      def to_s
        str = @name
        @options.each_with_index do |kv, i|
          str += (i == 0 ? ':' : ';')
          str += "#{kv[0]}=#{kv[1]}"
        end
        return str
      end

      def initialize(name, options={})
        @name = name
        @options = options || {}
      end

      def eql?(rhs)
        rhs && @name == rhs.name && @options == rhs.options
      end
      alias == eql?

      def hash()
        @name.hash
      end

      def <=>(rhs)
        return @name <=> rhs.name
      end
    end

  end
end

