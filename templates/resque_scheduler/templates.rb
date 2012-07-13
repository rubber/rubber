append_to_file 'Gemfile', "gem 'resque-scheduler'\n" if Rubber::Util::is_bundler?
