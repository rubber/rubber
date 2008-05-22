require 'fileutils'
require 'find'

class VulcanizeGenerator < Rails::Generator::NamedBase
  
  TEMPLATE_ROOT = File.dirname(__FILE__) + "/templates"
  TEMPLATE_FILE = "templates.yml"
    
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
    
    templ_conf = load_template_config(sp)
    deps = templ_conf['dependent_templates'] || []
    deps.each do |dep|
      apply_template(m, dep)
    end
    
    Find.find(sp) do |f|
      Find.prune if File.basename(f) =~ /^(CVS|\.svn)$/
      Find.prune if f == "#{sp}#{TEMPLATE_FILE}"
      rel = f.gsub(/#{source_root}\//, '')
      dest_rel = "config/" + rel.gsub(/^#{name}\//, '')
      m.directory(dest_rel) if File.directory?(f)
      m.file(rel, dest_rel) if File.file?(f)
    end
  end

  protected
    def valid_templates
      valid = Dir.entries(TEMPLATE_ROOT).delete_if {|e| e =~ /(^\.)|svn|CVS|Capfile/ }
    end
    
    def load_template_config(template_dir)
      templ_file = "#{template_dir}/templates.yml"
      templ_conf = YAML.load(File.read(templ_file)) rescue {}
      return templ_conf
    end

    def banner
      usage = "Usage: #{$0} vulcanize template_name\n"
      usage << "where template_name is one of:\n\n"
      valid_templates.each do |t|
        templ_conf = load_template_config("#{TEMPLATE_ROOT}/#{t}")
        desc = templ_conf['description']
        usage << "    #{t}: #{desc}\n" 
      end
      return usage
    end
end
