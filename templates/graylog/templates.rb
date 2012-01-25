if Rubber::Util::is_bundler?
  append_to_file "Gemfile", "gem 'gelf'\n"
  append_to_file "Gemfile", "gem 'graylog2_exceptions'\n"
end
