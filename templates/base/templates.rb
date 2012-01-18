if Rubber::Util::is_bundler?
  append_to_file "Gemfile", "gem 'rubber', '#{Rubber.version}'\n"
  
  # for cron-sh
  append_to_file 'Gemfile', "gem 'open4'\n"
  
end
