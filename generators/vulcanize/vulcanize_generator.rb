require 'fileutils'
require 'find'

class VulcanizeGenerator < Rails::Generator::NamedBase
  def manifest
    record do |m|
      sp = source_path("#{file_name}/")
      unless File.directory?(sp)
        templates = Dir.entries(source_root).delete_if {|e| e =~ /(^\.)|svn|CVS/ }
        raise Rails::Generator::UsageError.new("Invalid template #{file_name}, use one of #{templates.join(',')}")
      end

      Find.find(sp) do |f|
        Find.prune if f =~ /CVS|svn/
        rel = f.gsub(/#{source_root}\//, '')
        dest_rel = "config/" + rel.gsub(/#{file_name}\//, '')
        m.directory(dest_rel) if File.directory?(f)
        m.file(rel, dest_rel) if File.file?(f)
      end
    end
  end

  protected
    def banner
      "Usage: #{$0} vulcanize template_name"
    end
end
