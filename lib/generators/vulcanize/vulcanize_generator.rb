require 'find'
require 'yaml'

# Load and initialize rubber if it hasn't been already.
# This happens using the generator with Rails 2 and Rubber is not set up as a plugin.
unless defined?(Rubber)
  env = ENV['RUBBER_ENV'] ||= 'development'
  root = '.'

  require 'rubber'
  Rubber::initialize(root, env)
end

if Rubber::Util::is_rails2?
  require 'fileutils'
  require 'commands/generate'

  class VulcanizeGenerator < Rails::Generator::NamedBase
    include Rails::Generator::Commands

    TEMPLATE_ROOT = File.dirname(__FILE__) + "/templates" unless defined?(TEMPLATE_ROOT)
    TEMPLATE_FILE = "templates.yml" unless defined?(TEMPLATE_FILE)

    def manifest
      record do |m|
        templates = [file_name] + actions
        templates.each do |t|
          apply_template(m, t)
        end
      end
    end

    def apply_template(m, name)
      sp = source_path("#{name}/")
      unless File.directory?(sp)
        raise Rails::Generator::UsageError.new("Invalid template #{name}, use one of #{valid_templates.join(', ')}")
      end

      @template_dependencies ||= []

      templ_conf = load_template_config(sp)
      deps = templ_conf['dependent_templates'] || []
      @template_dependencies.concat(deps)
      deps.each do |dep|
        apply_template(m, dep)
      end

      extra_generator_steps_file = File.join(TEMPLATE_ROOT, name, 'templates.rb')

      Find.find(sp) do |f|
        Find.prune if File.basename(f) =~ /^(CVS|\.svn)$/
        Find.prune if f == "#{sp}#{TEMPLATE_FILE}"
        Find.prune if f == extra_generator_steps_file # don't copy over templates.rb

        rel = f.gsub(/#{source_root}\//, '')
        dest_rel = rel.gsub(/^#{name}\//, '')

        # Only include optional files when their conditions eval to true
        template_conf = YAML.load(File.read(TEMPLATE_FILE)) rescue {}
        optional = template_conf['optional'][dest_rel] rescue nil
        Find.prune if optional && ! eval(optional)

        m.directory(dest_rel) if File.directory?(f)
        if File.file?(f)
          # force scripts to be executable
          opts = (File.read(f) =~ /^#!/) ? {:chmod => 0755} : {}
          m.file(rel, dest_rel, opts)
        end
      end

      if File.exist? extra_generator_steps_file
        eval File.read(extra_generator_steps_file), binding, extra_generator_steps_file
      end
    end

    protected
      def valid_templates
        valid = Dir.entries(TEMPLATE_ROOT).delete_if {|e| e =~ /(^\.)|svn|CVS/ }
      end

      def load_template_config(template_dir)
        templ_file = "#{template_dir}/templates.yml"
        templ_conf = YAML.load(File.read(templ_file)) rescue {}
        return templ_conf
      end

      def banner
        usage = "Usage: #{$0} vulcanize template_name ...\n"
        usage << "where template_name is one of:\n\n"
        valid_templates.each do |t|
          templ_conf = load_template_config("#{TEMPLATE_ROOT}/#{t}")
          desc = templ_conf['description']
          usage << "    #{t}: #{desc}\n"
        end
        return usage
      end
  end

else
  require 'rails/generators'

  class VulcanizeGenerator < Rails::Generators::NamedBase

    def self.source_root
      File.join(File.dirname(__FILE__), 'templates')
    end

    def copy_template_files
      @template_dependencies = find_dependencies(file_name)
      ([file_name] + @template_dependencies).each do |template|
        apply_template(template)
      end
    end

    protected

    # helper to test for rails for optional templates
    def rails?
      Rubber::Util::is_rails?
    end

    def find_dependencies(name)
      template_dir = File.join(self.class.source_root, name, '')
      unless File.directory?(template_dir)
        raise Rails::Generators::Error.new("Invalid template #{name}, use one of #{valid_templates.join(', ')}")
      end

      template_conf = load_template_config(template_dir)
      template_dependencies = template_conf['dependent_templates'] || []

      template_dependencies.clone.each do |dep|
        template_dependencies.concat(find_dependencies(dep))
      end

      return template_dependencies.uniq
    end

    def apply_template(name)
      template_dir = File.join(self.class.source_root, name, '')
      unless File.directory?(template_dir)
        raise Rails::Generators::Error.new("Invalid template #{name}, use one of #{valid_templates.join(', ')}")
      end

      template_conf = load_template_config(template_dir)

      extra_generator_steps_file = File.join(template_dir, 'templates.rb')

      Find.find(template_dir) do |f|
        Find.prune if f == File.join(template_dir, 'templates.yml')  # don't copy over templates.yml
        Find.prune if f == extra_generator_steps_file # don't copy over templates.rb

        template_rel = f.gsub(/#{template_dir}/, '')
        source_rel = f.gsub(/#{self.class.source_root}\//, '')
        dest_rel   = source_rel.gsub(/^#{name}\//, '')

        # Only include optional files when their conditions eval to true
        optional = template_conf['optional'][template_rel] rescue nil
        Find.prune if optional && ! eval(optional)

        if File.directory?(f)
          empty_directory(dest_rel)
        else
          copy_file(source_rel, dest_rel)
          src_mode = File.stat(f).mode
          dest_mode = File.stat(File.join(destination_root, dest_rel)).mode
          chmod(dest_rel, src_mode) if src_mode != dest_mode
        end
      end

      if File.exist? extra_generator_steps_file
        eval File.read(extra_generator_steps_file), binding, extra_generator_steps_file
      end
    end

    def valid_templates
      valid = Dir.entries(self.class.source_root).delete_if {|e| e =~  /(^\.)|svn|CVS/ }
    end

    def load_template_config(template_dir)
      YAML.load(File.read(File.join(template_dir, 'templates.yml'))) rescue {}
    end
  end

end
