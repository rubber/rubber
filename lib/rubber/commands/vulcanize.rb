
# vulcanize is the only thing that needs thor in order to get the
# rails style generator capability
require 'thor'

module Rubber
  module Commands

    class Vulcanize < Clamp::Command
      
      def self.subcommand_name
        "vulcanize"
      end

      def self.subcommand_description
        "Installs rubber templates into project"
      end
      
      def self.description
        lines = []
        line = ""
        VulcanizeThor.valid_templates.each do |t|
          line << ", " if line.size > 0
          line << t
          if line.size > 55
            lines << line + ","
            line = ""
          end
        end
        lines << line if line.size >0
        
        Rubber::Util.clean_indent(<<-EOS
          Prepares the rails application for deploying with rubber by installing a
          sample rubber configuration template. e.g.
          
            rubber vulcanize complete_passenger_postgresql
          
          where TEMPLATE is one of:
          
          #{lines.join("\n")}
        EOS
        )
      end
      
      option ["-f", "--force"], :flag, "Overwrite files that already exist"
      option ["-p", "--pretend"], :flag, "Run but do not make any changes"
      option ["-q", "--quiet"], :flag, "Supress status output"
      option ["-s", "--skip"], :flag, "Skip files that already exist"
      
      parameter "TEMPLATE ...", "rubber template(s)" do |arg|
        invalid = arg - VulcanizeThor.valid_templates
        if invalid.size == 0
          arg
        else
          raise ArgumentError.new "Templates #{arg.inspect} don't exist"
        end
      end

      def execute
        v = VulcanizeThor.new([],
                              :force => force?,
                              :pretend => pretend?,
                              :quiet => quiet?,
                              :skip => skip?)
        v.vulcanize(template_list)
      end
      
    end
    
    class VulcanizeThor < Thor

      include Thor::Actions

      def self.source_root
        File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'templates'))
      end

      def self.valid_templates()
        valid = Dir.entries(self.source_root).delete_if {|e| e =~  /(^\.)|svn|CVS/ }
      end

      desc "vulcanize TEMPLATE", ""

      def vulcanize(template_names)
        @template_dependencies = template_names.collect {|t| [t] + find_dependencies(t) }.flatten.uniq
        @template_dependencies.each do |template|
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
          raise Thor::Error.new("Invalid template #{name}, use one of #{self.class.valid_templates.join(', ')}")
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
          raise Thor::Error.new("Invalid template #{name}, use one of #{self.class.valid_templates.join(', ')}")
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

      def load_template_config(template_dir)
        YAML.load(File.read(File.join(template_dir, 'templates.yml'))) rescue {}
      end

      def rubber_env()
        Rubber::Configuration.rubber_env
      end

      def rubber_instances()
        Rubber::Configuration.rubber_instances
      end

      def cloud_provider
        rubber_env.cloud_providers[rubber_env.cloud_provider]
      end

      def init_s3()
        AWS::S3::Base.establish_connection!(:access_key_id => cloud_provider.access_key, :secret_access_key => cloud_provider.secret_access_key)
      end

    end

  end
end
