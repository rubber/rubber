if Rubber::Util::is_bundler?
  append_to_file "Gemfile", "gem 'couchbase'\n"
end
