require "clamp"

# require all the rubber commands
files = Dir[File.expand_path(File.join(File.dirname(__FILE__), 'commands/*.rb'))]
files.each do |f|
  require f
end

module Rubber

  class CLI < Clamp::Command
    
    # setup clamp subcommands for each rubber command
    command_classes = []
    Rubber::Commands.constants.each do |c|
      clazz = Rubber::Commands.const_get(c)
      if clazz.class == Class && clazz.ancestors.include?(Clamp::Command) &&
         clazz.respond_to?(:subcommand_name) && clazz.respond_to?(:subcommand_description)
        subcommand clazz.subcommand_name, clazz.subcommand_description, clazz
      end
    end
    
    option ["-v", "--version"], :flag, "print version" do
      puts Rubber.version
      exit 0
    end
    
  end
  
end
