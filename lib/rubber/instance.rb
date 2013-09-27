require 'yaml'
require 'monitor'

module Rubber
  module Configuration

    # Contains the ec2 instance configuration defined in instance.yml
    #
    class Instance
      attr_reader :instance_storage, :artifacts
      include Enumerable
      include MonitorMixin

      def initialize(instance_storage, opts={})
        super()
        
        @instance_storage = instance_storage
        @opts = opts
      
        @items = {}
        @artifacts = {'volumes' => {}, 'static_ips' => {}}

        @filters = Rubber::Util::parse_aliases(ENV['FILTER'])
        @filters, @filters_negated = @filters.partition {|f| f !~ /^-/ }
        @filters_negated = @filters_negated.collect {|f| f[1..-1] }

        @filter_roles = Rubber::Util::parse_aliases(ENV['FILTER_ROLES'])
        @filter_roles, @filter_roles_negated = @filter_roles.partition {|f| f !~ /^-/ }
        @filter_roles_negated = @filter_roles_negated.collect {|f| f[1..-1] }

        load()
      end
      
      def load(instance_storage=@instance_storage)
        case instance_storage
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
            raise "Invalid instance_storage: #{instance_storage}\n" +
                "Must be one of file:, table:, storage:"
        end
      end

      def load_from_file(io)
        item_list =  YAML.load(io.read)
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
      
      def save(instance_storage=@instance_storage, backup=@opts[:backup])
        synchronize do
          case instance_storage
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
              raise "Invalid instance_storage: #{instance_storage}\n" +
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

      def filtered()
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

      def validate_filters()
        aliases = @items.values.collect{|ic| ic.name}
        [@filters, @filters_negated].flatten.each do |f|
          raise "Filter doesn't match any hosts: #{f}" if ! aliases.include?(f)
        end

        roles = all_roles
        [@filter_roles, @filter_roles_negated].flatten.each do |f|
          raise "Filter doesn't match any roles: #{f}" if ! roles.include?(f)
        end
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
      attr_reader :name, :domain, :instance_id, :image_type, :image_id, :security_groups
      attr_accessor :roles, :zone
      attr_accessor :external_host, :external_ip
      attr_accessor :internal_host, :internal_ip
      attr_accessor :static_ip, :volumes, :partitions, :root_device_type
      attr_accessor :spot_instance_request_id
      attr_accessor :provider, :platform

      def initialize(name, domain, roles, instance_id, image_type, image_id, security_group_list=[])
        @name = name
        @domain = domain
        @roles = roles
        @instance_id = instance_id
        @image_type = image_type
        @image_id = image_id
        @security_groups = security_group_list
      end

      def self.from_hash(hash)
        item = allocate
        hash.each do |k, v|
          sym = "@#{k}".to_sym
          v = v.collect {|r| RoleItem.parse(r) } if k == 'roles'
          item.instance_variable_set(sym, v)
        end
        return item
      end
      
      def to_hash
        hash = {}
        instance_variables.each do |iv|
          name = iv.to_s.gsub(/^@/, '')
          value = instance_variable_get(iv)
          value = value.collect {|r| r.to_s } if name == 'roles'
          hash[name] = value
        end
        return hash
      end
      
      def <=>(rhs)
        name <=> rhs.name
      end
      
      def full_name
        "#@name.#@domain"
      end

      def role_names()
        roles.collect {|r| r.name}
      end

      def provider
        # Deal with old instance configurations that don't have a provider value persisted.
        @provider || 'aws'
      end

      def platform
        # Deal with old instance configurations that don't have a platform value persisted.
        @platform || 'linux'
      end

      def linux?
        platform == 'linux'
      end

      def mac?
        platform == 'mac'
      end

      def windows?
        platform == 'windows'
      end
    end

    # The configuration for a single role contained in the list
    # of roles in InstanceItem
    class RoleItem
      attr_reader :name, :options

      def self.expand_role_dependencies(roles, dependency_map, expanded=[])
        roles = Array(roles)

        if expanded.size == 0
          common_deps = Array(dependency_map[RoleItem.new('common')])
          roles.concat(common_deps)
        end

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
        data = str.split(':')
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

