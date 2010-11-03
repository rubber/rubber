gem "rubber", Rubber.version if Rubber::Util::is_bundler? && ! Rubber::Util::rubber_as_plugin?

if Rubber::Util::is_rails2?
  m.gsub_file('script/cron-runner', /RAILS_RUNNER/, 'script/runner')
  m.gsub_file('Rakefile', /RAILS_LOADER/, "require(File.join(File.dirname(__FILE__), 'config', 'boot'))")
  m.gsub_file('Rakefile', /RAILS_TASKS/, "require 'tasks/rails'")
else
  gsub_file('script/cron-runner', /RAILS_RUNNER/, 'rails runner')
  gsub_file('Rakefile', /RAILS_LOADER/, '')
  gsub_file('Rakefile', /RAILS_TASKS/, '')
end
