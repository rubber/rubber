$:.unshift "#{File.dirname(__FILE__)}/../lib"

require 'rubber'
Rubber::initialize(File.dirname(__FILE__), 'test')

require 'test/unit'
require 'mocha/setup'
require 'shoulda-context'
require 'pp'
require 'ap'
require 'tempfile'
require 'fog'

module Rubber; @@logger = Logger.new("/dev/null"); end

if defined?(JRUBY_VERSION)
  require 'unlimited-strength-crypto'
end

class Test::Unit::TestCase
  # ENV['NO_FOG_MOCK'] = 'true'
  
  setup do
    Fog.mock! unless ENV['NO_FOG_MOCK'] 
  end
  
  teardown do
    Fog::Mock.reset unless ENV['NO_FOG_MOCK'] 
  end
end


SECRET = YAML.load_file(File.expand_path("~/rubber-secret.yml")) rescue {}

def get_secret(path)
  parts = path.split('.')
  result = SECRET
  
  parts.each do |part|
    result = result[part] if result
  end
  return result
end

TEST_DOMAIN = 'rubbertester'

def all_test_zones(dns)
  dns.client.zones.all.find_all {|z| z.domain =~ /#{TEST_DOMAIN}/ }
end

def destroy_test_domains(dns)
  all_test_zones(dns).each do |zone|
    # hardcoded failsafe to prevent destruction of real domains
    raise "Trying to destroy non-rubber domain!" if zone.domain !~ /rubber/
    
    while zone.records.all.size != 0
      zone.records.all.each do |record|
        record.destroy
      end
    end
    zone.destroy
  end
end
