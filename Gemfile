source "https://rubygems.org"

gem 'jruby-openssl', :platform => :jruby
gem 'unlimited-strength-crypto', :platform => :jruby

group :development do
  gem 'httparty'
  # Need to run off master for tests until updated Digital Ocean mocking
  # makes it into a release
  gem 'fog', :git => 'https://github.com/fog/fog.git', :branch => 'master'
  gem 'vcr'
  gem 'webmock'
end

# Specify your gem's dependencies in rubber.gemspec
gemspec
