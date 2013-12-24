# Overrides a method in Capistrano::Configuration::Servers.  That method allows for configured default_run_options to
# override the options defined on the task itself.  The problem is it doesn't do a deep merge, so any option that is
# a hash ends up being completely overwritten rather than being merged itself.  What we're doing here does break the
# defined contract for Capistrano, but should be equivalent in non-deep merge scenarios.  We need the deep merge in
# order to specify both a :platform (as a default_run_option) and :primary (as a task option) hash value for the
# :only option.  NB: For simplicity we're only "deep merging" one level deep, in order to meet our immediate use case.
#
# We shouldn't make a habit of patching Capistrano in Rubber. But since Capistrano 2.x is effectively a dead project,
# getting this fixed upstream is extremely unlikely.

module Capistrano
  class Configuration
    def find_servers_for_task(task, options = {})
      find_options = task.options.dup
      options.each do |k, v|
        if find_options[k].is_a?(Hash)
          find_options[k].merge!(v)
        else
          find_options[k] = v
        end
      end

      find_servers(find_options)
    end
  end
end