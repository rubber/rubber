append_to_file 'Gemfile', "gem 'rack-flash'\n" if Rubber::Util::is_bundler?
append_to_file 'Gemfile', "gem 'googlecharts'\n" if Rubber::Util::is_bundler?
append_to_file 'Gemfile', "gem 'google_visualr'\n" if Rubber::Util::is_bundler?