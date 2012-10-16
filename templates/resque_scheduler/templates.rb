append_to_file 'Gemfile', "gem 'resque-scheduler', :require => ['resque_scheduler', 'resque_scheduler/server']\n" if Rubber::Util::is_bundler?
