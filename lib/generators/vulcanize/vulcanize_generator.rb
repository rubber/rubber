require 'rails/generators'
require 'find'
require 'yaml'

class VulcanizeGenerator < Rails::Generators::NamedBase

  def self.source_root
    File.join(File.dirname(__FILE__), 'templates')
  end

  def copy_template_files
    apply_template(file_name)
    gem "rubber", Rubber.version if Rubber::Util::is_bundler?
  end

  protected

  # helper to test for rails for optional templates
  def rails?
    Rubber::Util::is_rails?
  end
  
  def apply_template(name)
    template_dir = File.join(self.class.source_root, name, '')
    unless File.directory?(template_dir)
      raise Rails::Generators::Error.new("Invalid template #{name}, use one of #{valid_templates.join(', ')}")
    end

    template_conf = load_template_config(template_dir)
    deps = template_conf['dependent_templates'] || []
    deps.each do |dep|
      apply_template(dep)
    end

    extra_generator_steps_file = File.join(template_dir, 'templates.rb')
    if File.exist? extra_generator_steps_file
      eval File.read(extra_generator_steps_file), binding, extra_generator_steps_file
    end

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
  end

  def valid_templates
    valid = Dir.entries(self.class.source_root).delete_if {|e| e =~  /(^\.)|svn|CVS/ }
  end

  def load_template_config(template_dir)
    YAML.load(File.read(File.join(template_dir, 'templates.yml'))) rescue {}
  end

end
