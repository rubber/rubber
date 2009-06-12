$:.unshift "#{File.dirname(__FILE__)}/../lib"

require 'rubber'
Rubber::initialize(File.dirname(__FILE__), 'test')
