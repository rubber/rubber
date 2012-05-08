$:.unshift "#{File.dirname(__FILE__)}/../lib"

require 'rubber'
Rubber::initialize(File.dirname(__FILE__), 'test')

require 'test/unit'
require 'mocha'
require 'shoulda-context'
require 'pp'
require 'ap'
require 'tempfile'
require 'fog'

class Test::Unit::TestCase
  setup do
    Fog.mock!
  end
  
  teardown do
    Fog::Mock.reset    
  end
end
