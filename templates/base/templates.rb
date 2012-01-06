if Rubber::Util::is_bundler?
  if ! Rubber::Util::rubber_as_plugin?
    append_to_file "Gemfile", "gem 'rubber', '#{Rubber.version}'\n"
  end
  
  # for cron-sh
  append_to_file 'Gemfile', "gem 'open4'\n"
end
