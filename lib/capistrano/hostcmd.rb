require 'capistrano/command'

# capistrano hack to allow us to run slightly different commands on multiple
# hosts in parallel
module Capistrano
  class Command
    def replace_placeholders(command, channel)
      command = command.gsub(/\$CAPISTRANO:HOST\$/, channel[:host])
      command.gsub(/\$CAPISTRANO:VAR\$/, @options["hostvar_#{channel[:host]}"].to_s)
    end
  end
end
