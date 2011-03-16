

module Rubber
  module Util

    def self.symbolize_keys(map)
      map.inject({}) do |options, (key, value)|
        options[key.to_sym || key] = value
        options
      end
    end
    
    def self.stringify(val)
      case val
      when String
        val
      when Hash
        val.inject({}) {|h, a| h[stringify(a[0])] = stringify(a[1]); h}
      when Enumerable
        val.collect {|v| stringify(v)}
      else
        val.to_s
      end
      
    end

    def self.parse_aliases(instance_aliases)
      aliases = []
      alias_patterns = instance_aliases.to_s.strip.split(/\s*,\s*/)
      alias_patterns.each do |a|
        if a =~ /~/
          range = a.split(/~/)
          range_items = (range.first..range.last).to_a
          raise "Invalid range, '#{a}', sequence generated no items" if range_items.size == 0
          aliases.concat(range_items)
        else
          aliases << a
        end
      end
      return aliases
    end

    # Opens the file for writing by root
    def self.sudo_open(path, perms, &block)
      open("|sudo tee #{path} > /dev/null", perms, &block)
    end

    def self.is_rails?
      File.exist?(File.join(RUBBER_ROOT, 'config', 'boot.rb'))
    end

    def self.is_rails2?
      defined?(Rails) && defined?(Rails::VERSION) && Rails::VERSION::MAJOR == 2
    end

    def self.is_rails3?
      defined?(Rails) && defined?(Rails::VERSION) && Rails::VERSION::MAJOR == 3
    end

    def self.is_bundler?
      File.exist?(File.join(RUBBER_ROOT, 'Gemfile'))
    end

    def self.rubber_as_plugin?
      File.exist?(File.join(RUBBER_ROOT, 'vendor/plugins/rubber'))
    end

    def self.prompt(name, desc, required=false, default=nil)
      value = ENV.delete(name)
      msg = "#{desc}"
      msg << " [#{default}]" if default
      msg << ": "
      unless value
        print msg
        value = gets
      end
      value = value.size == 0 ? default : value
      self.fatal "#{name} is required, pass using environment or enter at prompt" if required && ! value
      return value
    end

    def self.fatal(msg, code=1)
      puts msg
      exit code
    end
    
  end
end
