append_to_file 'Gemfile', "gem 'resque-scheduler', :require => ['resque-scheduler', 'resque/scheduler/server']\n" if Rubber::Util::is_bundler?
