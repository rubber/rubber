require 'rubber'

env = ENV['RUBBER_ENV'] ||= (ENV['RAILS_ENV'] || 'development')
root = File.dirname(__FILE__) + '/../..'
Rubber::initialize(root, env

require 'rubber/tasks/rubber'
