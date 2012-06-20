append_to_file 'Gemfile', "gem 'sidekiq'\n" if Rubber::Util::is_bundler?
append_to_file 'Gemfile', "gem 'slim'\n" if Rubber::Util::is_bundler?
