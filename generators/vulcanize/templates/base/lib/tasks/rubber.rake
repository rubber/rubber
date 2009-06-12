require 'rubber'
Rubber::initialize(File.dirname(__FILE__) + '../../', (ENV['RAILS_ENV'] ||= 'development'))
require 'rubber/tasks/rubber.rake'
