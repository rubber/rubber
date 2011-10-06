if Rubber::Util::is_bundler?
  gem "rubber", Rubber.version if ! Rubber::Util::rubber_as_plugin?
  # for cron-sh
  gem "open4"
end

if Rubber::Util::is_rails2?
  m.gsub_file('script/cron-runner', /RAILS_RUNNER/, 'script/runner')
else
  gsub_file('script/cron-runner', /RAILS_RUNNER/, 'rails runner')
end
