require 'logger'
require 'yaml'
require 'erb'
require 'find'
require 'fileutils'
require 'socket'

module Rubber
  module Configuration

    LOGGER = Logger.new($stdout)
    LOGGER.level = Logger::DEBUG
    LOGGER.formatter = lambda {|severity, time, progname, msg| "Rubber[%s]: %s\n" % [severity, msg.to_s.lstrip]}

    @@configurations = {}

    def self.get_configuration(env=nil, root=nil)
      key = "#{env}-#{root}"
      @@configurations[key] ||= ConfigHolder.new(env, root)
    end


    class ConfigHolder
      def initialize(env=nil, root=nil)
        root = "config/rubber" unless root
        instance_cfg =  "#{root}/instance" + (env ? "-#{env}.yml" : ".yml")
        @environment = Environment.new("#{root}/rubber.yml")
        @instance = Instance.new(instance_cfg)
      end

      def environment
        @environment
      end

      def instance
        @instance
      end
    end

    # Contains the configuration defined in rubber.yml
    # Handles selecting of correct config values based on
    # the host/role passed into bind
    class Environment
      attr_reader :file

      def initialize(file)
        LOGGER.info{"Reading rubber configuration from #{file}"}
        @file = file
        @items = {}
        if File.exist?(@file)
          @items = YAML.load(File.read(@file)) || {}
        end
      end

      def known_roles
        roles_dir = File.join(File.dirname(@file), "role")
        roles = Dir.entries(roles_dir)
        roles.delete_if {|d| d =~ /(^\..*)/}
      end

      def bind(role, host)
        BoundEnv.new(@items, role, host)
      end

      class BoundEnv
        def initialize(cfg, role, host)
          @cfg = cfg
          @role = role
          @host = host
        end

        def [](name)
           (@cfg["hosts"][@host][name] rescue nil) || (@cfg["roles"][@role][name] rescue nil) || @cfg[name]
        end

        def method_missing(method_id)
          key = method_id.id2name
          self[key]
        end
      end

    end

    # Contains the ec2 instance configuration defined in instance.yml
    #
    class Instance
      attr_reader :file

      def initialize(file)
        LOGGER.info{"Reading rubber instances from #{file}"}
        @file = file
        @items = {}
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

      def for_role(role_name)
        @items.collect {|n, i| i if i.roles.any? {|r| r.name == role_name }}.compact
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
    end

    # The configuration for a single instance
    class InstanceItem
      attr_reader :name, :roles, :instance_id
      attr_accessor :external_host, :external_ip
      attr_accessor :internal_host, :internal_ip

      def initialize(name, roles, instance_id)
        @name = name
        @roles = roles
        @instance_id = instance_id
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

    # Instances of this object are used accept settings from with
    # a config file for when it is transformed by Generator
    class ConfigDescriptor
      # The output path to write the transformed config file to
      attr_accessor :path
      # The command to use for reading the original config file from (e.g. "crontab -l")
      attr_accessor :read_cmd
      # The command to use for piping the transformed config file to (e.g. "crontab -")
      attr_accessor :write_cmd
      # The command to run after generating the config file if it has changed
      attr_accessor :post
      # The owner the output file should have, e.g. "root"
      attr_accessor :owner
      # The group the output file should have, e.g. "system"
      attr_accessor :group
      # The permissions the output file should have, e.g. 644
      attr_accessor :perms
      # Sets transformation to be additive, only replaces between given delimiters, e/g/ additive = ["## start", "## end"]
      attr_accessor :additive
      # use sudo to write the output file
      # attr_accessor :sudo
      # options passed in through code
      attr_accessor :options

      def get_binding
        binding
      end

      def rubber_instances
        Rubber::Configuration.get_configuration(RAILS_ENV).instance
      end

      def rubber_env
        cfg = Rubber::Configuration.get_configuration(RAILS_ENV)
        role = cfg.instance.roles.first.name rescue nil
        host = Socket::gethostname.gsub(/\..*/, '')
        cfg.environment.bind(role, host)
      end
    end

    # Handles selection and transformation of a set of config files
    # based on the host/role they belong to
    class Generator
      attr_accessor :file_pattern
      attr_accessor :no_post

      def initialize(config_dir, roles, host, options={})
        @config_dir = config_dir
        @roles = roles.to_a.reverse #First roles take precedence
        @host = host || 'no_host'
        @options=options
      end

      def run
        config_dirs = []
        config_dirs << "#{@config_dir}/common/"
        @roles.each {|role| config_dirs <<  "#{@config_dir}/role/#{role}" }
        config_dirs << "#{@config_dir}/host/#{@host}"

        pat = Regexp.new(file_pattern) if file_pattern

        Find.find(*config_dirs) do |f|
          if File.file?(f) && (! pat || pat.match(f))
            LOGGER.info{"Transforming #{f}"}
            transform(IO.read(f), @options)
          end
          Find.prune if f =~ /CVS|svn/
        end
      end

      # Transforms the ERB template given in srcfile and writes the result to
      # dest_file (if not nil) before returning it
      def transform(src_data, options={})
        config = ConfigDescriptor.new
        config.options = options
        template = ERB.new(src_data)
        result = template.result(config.get_binding())

        if ! config.path && ! (config.read_cmd && config.write_cmd)
          raise "Transformation requires either a output filename or command"
        end

        reader = config.path || "|#{config.read_cmd}"
        orig = IO.read(reader) rescue nil

        # When additive is set we need to only replace between our delimiters
        if config.additive
          pat = /#{config.additive[0]}.*#{config.additive[1]}/m
          new = "#{config.additive[0]}#{result}#{config.additive[1]}"
          if orig =~ pat
            result = orig.gsub(pat, new)
          else
            result = orig + new + "\n"
          end
        end

        # Only do something if the transformed result is different than what
        # is currently in the destination file
        if orig != result
          # create dirs as needed
          FileUtils.mkdir_p(File.dirname(config.path)) if config.path

          # Write a backup of original
          open("#{config.path}.bak", 'w') { |f| f.write(orig) } if config.path

          # Write out transformed file
          writer = config.path || "|#{config.write_cmd}"
          open(writer, 'w') do |pipe|
            pipe.write(result)
          end

          # Set file permissions and owner if needed
          File.chmod(config.perms, config.path) if config.perms && config.path
          File.chown(config.owner, config.group, config.path) if config.path && (config.owner || config.group)

          # Run post transform command if needed
          if config.post && orig != result && ! no_post
            LOGGER.info{"Transformation executing post config command: #{config.post}"}
            LOGGER.info `#{config.post}`
          end
        end
      end

    end

  end
end