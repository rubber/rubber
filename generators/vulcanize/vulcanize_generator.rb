require 'fileutils'
require 'find'

class VulcanizeGenerator < Rails::Generator::NamedBase
  def manifest
    record do |m|
      sp = source_path("#{file_name}/")
      unless File.directory?(sp)
        raise Rails::Generator::UsageError.new("Invalid template #{file_name}, use one of #{valid_templates.join(', ')}")
      end

      Find.find(sp) do |f|
        Find.prune if f =~ /^(CVS|\.svn)$/
        rel = f.gsub(/#{source_root}\//, '')
        dest_rel = "config/" + rel.gsub(/#{file_name}\//, '')
        m.directory(dest_rel) if File.directory?(f)
        m.file(rel, dest_rel) if File.file?(f)
      end
      m.file("Capfile", "Capfile")
    end
  end

  protected
    def valid_templates
      valid = Dir.entries(File.dirname(__FILE__) + "/templates").delete_if {|e| e =~ /(^\.)|svn|CVS/ }
    end

    def banner
      "Usage: #{$0} vulcanize template_name\n\twhere template_name is one of #{valid_templates.join(', ')}"
    end
end
