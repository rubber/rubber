$:.unshift "#{File.dirname(__FILE__)}/../lib"

require 'rubber'
Rubber::initialize(File.dirname(__FILE__), 'test')

require 'rubygems'
require 'mocha'
require 'pp'
require 'fakeweb'
FakeWeb.allow_net_connect = false

def fakeweb_fixture(name)
  return File.read("#{File.dirname(__FILE__)}/fixtures/fakeweb/#{name}")
end