require File.expand_path(File.join(__FILE__, '..', 'test_helper'))
require 'rubber/dns'
require 'rubber/dns/zerigo'
require 'rexml/document'

class ZerigoTest < Test::Unit::TestCase

  def setup
    env = Rubber::Configuration::Environment::BoundEnv.new({'dns_providers' => {'zerigo' => {'email' => 'foo@bar.com', 'token' => 'testtoken'}}}, nil, nil)
    @dns = Rubber::Dns::Zerigo.new(env)
    @fog = Fog::DNS.new({:provider => 'Zerigo', :zerigo_email => @dns.provider_env.email, :zerigo_token => @dns.provider_env.token })

    @domain = "example1.com"
    @zone = @fog.zones.create(:domain => @domain)
  end

  def test_find_records
    # Set up some sample records.
    first = @zone.records.create(:value => '172.16.16.1', :name => 'host1', :domain => @domain, :type => 'A')
    @zone.records.create(:value => '172.16.16.2', :domain => @domain, :type => 'A')

    # Search for records through the rubber DNS interface and make sure whe get what we expected.

    # Wildcard search.
    records = @dns.find_host_records(:host => '*', :domain => @domain)
    assert_equal 2, records.size
    assert_equal({:type => "A", :host => "host1", :domain => @domain, :id => first.id, :data=>"172.16.16.1", :ttl => 3600, :priority => 0}, records.first)

    # Blank hostname search.
    records = @dns.find_host_records(:host => '', :domain => @domain)
    assert_equal 1, records.size
    assert_equal '', records.first[:host]

    # Specific hostname search.
    records = @dns.find_host_records(:host => 'host1', :domain => @domain)
    assert_equal 1, records.size
    assert_equal 'host1', records.first[:host]
  end

  def test_create_record
    @dns.create_host_record({:host => 'newhost', :domain => @domain, :data => '1.1.1.1', :type => 'A', :ttl => '333'})

    assert_equal @zone.records.all.size, 1
    record = @zone.records.first

    assert_equal 'newhost',             record.name
    assert_equal "newhost.#{@domain}",  record.domain
    assert_equal '1.1.1.1',             record.value
    assert_equal 'A',                   record.type
    assert_equal 333,                   record.ttl
  end

  def test_destroy_record
    # Create the record we want to test destroying.
    @zone.records.create(:type => 'A', :value => '172.16.16.1', :name => 'host1', :domain => @domain)
    assert_equal 1, @zone.records.all.size

    @dns.destroy_host_record({:host => 'host1', :domain => @domain})

    assert_equal 0, @zone.records.all.size
  end

  def test_update_record
    params = {:host => 'host1', :domain => @domain, :data => "1.1.1.1"}
    new = {:host => 'host1', :domain => @domain, :data => "1.1.1.2"}

    @zone.records.create(:type => 'A', :value => '1.1.1.1', :name => 'host1', :domain => @domain)

    @dns.update_host_record(params, new)

    record = @zone.records.all.first
    assert_equal '1.1.1.2', record.value
  end

end
