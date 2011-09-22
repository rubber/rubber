
module Rubber
  module Commands

    class Vulcanize < Thor

      namespace :default

      include Thor::Actions
      add_runtime_options!

      def self.source_root
        File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'templates'))
      end

      def self.valid_templates()
        valid = Dir.entries(self.source_root).delete_if {|e| e =~  /(^\.)|svn|CVS/ }
      end

      desc "vulcanize TEMPLATE", Rubber::Util.clean_indent(<<-EOS
        Prepares the rails application for deploying with rubber by installing
        a sample rubber configuration template.

          e.g. rubber vulcanize complete_passenger_postgresql

        where TEMPLATE is one of:
          #{valid_templates.join(", ")}
      EOS
      )

      def vulcanize(template_name)
        (template_name)
        @template_dependencies = find_dependencies(template_name)
        ([template_name] + @template_dependencies).each do |template|
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
