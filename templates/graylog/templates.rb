if Rubber::Util::is_bundler?
  append_to_file "Gemfile", "gem 'gelf'\n"
  append_to_file "Gemfile", "gem 'graylog2_exceptions', :git => 'git://github.com/wr0ngway/graylog2_exceptions.git'\n"
  append_to_file "Gemfile", "gem 'graylog2-resque'\n"
end
