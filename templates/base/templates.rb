if Rubber::Util::is_bundler?
  append_to_file "Gemfile", "gem 'rubber'\n"
  
  # for cron-sh
  append_to_file 'Gemfile', "gem 'open4'\n"
  
  # TODO: remove this once 12.04 is fixed
  # temp workaround for https://github.com/rubygems/rubygems/issues/319
  gsub_file 'Gemfile', /source (["'])https/, 'source \1http'
  
end
