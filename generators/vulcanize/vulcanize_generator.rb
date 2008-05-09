require 'fileutils'
require 'find'

class VulcanizeGenerator < Rails::Generator::NamedBase
  
  def manifest
    record do |m|
      apply_template(m, file_name)
      m.file("Capfile", "Capfile")
    end
  end

  def apply_template(m, name)
    sp = source_path("#{name}/")
    unless File.directory?(sp)
      raise Rails::Generator::UsageError.new("Invalid template #{name}, use one of #{valid_templates.join(', ')}")
    end
    
    templ_file = "#{sp}templates.yml"
    templ_conf = YAML.load(File.read(templ_file)) rescue {}
    deps = templ_conf['dependent_templates'] || []
    deps.each do |dep|
      apply_template(m, dep)
    end
    
    Find.find(sp) do |f|
      Find.prune if File.basename(f) =~ /^(CVS|\.svn)$/
      Find.prune if f == templ_file
      rel = f.gsub(/#{source_root}\//, '')
      dest_rel = "config/" + rel.gsub(/#{name}\//, '')
      m.directory(dest_rel) if File.directory?(f)
      m.file(rel, dest_rel) if File.file?(f)
    end
  end

  protected
    def valid_templates
      valid = Dir.entries(File.dirname(__FILE__) + "/templates").delete_if {|e| e =~ /(^\.)|svn|CVS|Capfile/ }
    end

    def banner
      "Usage: #{$0} vulcanize template_name\n\twhere template_name is one of #{valid_templates.join(', ')}"
    end
end
