append_to_file 'Gemfile', "gem 'passenger'\n" if Rubber::Util::is_bundler?
