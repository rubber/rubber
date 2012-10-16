append_to_file 'Gemfile', "gem 'resque', :require => 'resque/server'\n" if Rubber::Util::is_bundler?
append_to_file 'Gemfile', "gem 'resque-pool'\n" if Rubber::Util::is_bundler?
append_to_file 'Gemfile', "gem 'puma'\n" if Rubber::Util::is_bundler?
