$:.unshift "#{File.dirname(__FILE__)}/../lib"

require 'rubber'
Rubber::initialize(File.dirname(__FILE__), 'test')

require 'test/unit'
require 'mocha'
require 'shoulda-context'
require 'pp'
require 'tempfile'

require 'fog'
Fog.mock!

class Test::Unit::TestCase
  def teardown
    Fog::Mock.reset    
  end
end
