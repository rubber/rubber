require 'rails/generators'
require 'find'

class VulcanizeGenerator < Rails::Generators::NamedBase

  def self.source_root
    File.join(File.dirname(__FILE__), 'templates')
  end

  def copy_template_files
    apply_template(file_name)
  end

   protected

    def apply_template(name)
      template_dir = File.join(self.class.source_root, name)
      unless File.directory?(template_dir)
        raise Rails::Generators::Error.new("Invalid template #{name}, use one of #{valid_templates.join(', ')}")
      end

      template_conf = load_template_config(template_dir)
      deps = template_conf['dependent_templates'] || []
      deps.each do |dep|
        apply_template(dep)
      end

      Find.find(File.join(template_dir, 'config')) do |f|
       source_rel = f.gsub(/#{self.class.source_root}\//, '')
        dest_rel   = source_rel.gsub(/^#{name}\//, '')
        if File.directory?(f)
          empty_directory(dest_rel)
        else
          copy_file(source_rel, dest_rel)
        end
      end
#      source_rel = File.join(template_dir.gsub(/#{self.class.source_root}\//, ''), 'config')
#      dest_rel = source_rel.gsub(/^#{name}\//, '')
#      directory(source_rel, dest_rel)
    end

     def valid_templates
       valid = Dir.entries(self.class.source_root).delete_if {|e| e =~  /(^\.)|svn|CVS/ }
     end
 
    def load_template_config(template_dir)
      YAML.load(File.read(File.join(template_dir, 'templates.yml'))) rescue {}
    end
end
