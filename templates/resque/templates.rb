append_to_file 'Gemfile', "gem 'resque'\n" if Rubber::Util::is_bundler?
append_to_file 'Gemfile', "gem 'resque-pool'\n" if Rubber::Util::is_bundler?
