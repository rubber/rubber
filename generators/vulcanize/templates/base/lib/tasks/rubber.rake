require 'rubber'

env = ENV['RAILS_ENV'] || ENV['RUBBER_ENV'] || 'development'
Rubber::initialize(File.dirname(__FILE__) + '/../..', env)

require 'rubber/tasks/rubber'
