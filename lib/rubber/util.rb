

module Rubber
  module Util

    def symbolize_keys(map)
      map.inject({}) do |options, (key, value)|
        options[key.to_sym || key] = value
        options
      end
    end
    
    def stringify_keys(map)
      map.inject({}) do |options, (key, value)|
        options[key.to_s || key] = value
        options
      end
    end
    
    def stringify(val)
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

    def parse_aliases(instance_aliases)
      aliases = []
      alias_patterns = instance_aliases.to_s.strip.split(/\s*,\s*/)
      alias_patterns.each do |a|
        if a =~ /~/
          range = a.split(/\s*~\s*/)
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
    def sudo_open(path, perms, &block)
      open("|sudo tee #{path} > /dev/null", perms, &block)
    end

    def is_rails?
      File.exist?(File.join(Rubber.root, 'config', 'boot.rb'))
    end

    def is_bundler?
      File.exist?(File.join(Rubber.root, 'Gemfile'))
    end

    def has_asset_pipeline?
      is_rails? && Dir["#{Rubber.root}/*/assets"].size > 0
    end

    def prompt(name, desc, required=false, default=nil)
      value = ENV.delete(name)
      msg = "#{desc}"
      msg << " [#{default}]" if default
      msg << ": "
      unless value
        print msg
        value = gets
      end
      value = value.size == 0 ? default : value
      fatal "#{name} is required, pass using environment or enter at prompt" if required && ! value
      return value
    end

    def fatal(msg, code=1)
      puts msg
      exit code
    end

    # remove leading whitespace from "here" strings so they look good in code
    # skips empty lines
    def clean_indent(str)
      str.lines.collect do |line|
        if line =~ /\S/ # line has at least one non-whitespace character
          line.lstrip
        else
          line
        end
      end.join()
    end

    # execute the given block, retrying only when one of the given exceptions is raised
    def retry_on_failure(*exception_list)
      opts = exception_list.last.is_a?(Hash) ? exception_list.pop : {}
      opts = {:retry_count => 3}.merge(opts)
      retry_count = opts[:retry_count]
      begin
        yield
      rescue *exception_list => e
        if retry_count > 0
          retry_count -= 1
          Rubber.logger.info "Exception, trying again #{retry_count} more times"
          sleep opts[:retry_sleep].to_i if opts[:retry_sleep] 
          retry
        else
          Rubber.logger.error "Too many exceptions...re-raising"
          raise
        end
      end
    end

    def camelcase(str)
      str.split('_').map{ |part| part.capitalize }.join
    end

    extend self
  end
end
