require 'rubygems'
gem 'test-unit'

require 'test/unit'
require File.expand_path(File.join(__FILE__, '..', 'test_helper'))
require 'rubber/dns'
require 'rubber/dns/zerigo'
require 'rexml/document'

class ZerigoTest < Test::Unit::TestCase

  def setup
    env = Rubber::Configuration::Environment::BoundEnv.new({'dns_providers' => {'zerigo' => {'email' => 'foo@bar.com', 'token' => 'testtoken'}}}, nil, nil)
    @dns = Rubber::Dns::Zerigo.new(env)
    FakeWeb.register_uri(:get,
                         "https://foo%40bar.com:testtoken@ns.zerigo.com/api/1.1/zones.xml",
                         :body => fakeweb_fixture('zerigo/get_zones.xml'))
    @domain = "example1.com"
    @zone = ::Zerigo::DNS::Zone.find_or_create(@domain)
  end

  def test_find_records
    hosts_xml = fakeweb_fixture('zerigo/get_hosts.xml')
    FakeWeb.register_uri(:get,
                         "https://foo%40bar.com:testtoken@ns.zerigo.com/api/1.1/hosts.xml?zone_id=1",
                         :body => hosts_xml)
    records = @dns.find_host_records(:host => '*', :domain => 'example1.com')
    assert_equal 2, records.size
    assert_equal({:type=>"A", :host=>"host1", :domain=>"example1.com", :id=>1, :data=>"172.16.16.1"}, records.first)

    doc = REXML::Document.new(hosts_xml)
    doc.root.elements.delete(1)
    hosts_xml_single = doc.to_s
    FakeWeb.register_uri(:get,
                         "https://foo%40bar.com:testtoken@ns.zerigo.com/api/1.1/hosts.xml?fqdn=example1.com&zone_id=1",
                         :body => hosts_xml_single)
    records = @dns.find_host_records(:host => '', :domain => 'example1.com')
    assert_equal 1, records.size
    assert_equal '', records.first[:host]

    doc = REXML::Document.new(hosts_xml)
    doc.root.elements.delete(2)
    hosts_xml_single = doc.to_s
    FakeWeb.register_uri(:get,
                         "https://foo%40bar.com:testtoken@ns.zerigo.com/api/1.1/hosts.xml?fqdn=host1.example1.com&zone_id=1",
                         :body => hosts_xml_single)
    records = @dns.find_host_records(:host => 'host1', :domain => 'example1.com')
    assert_equal 1, records.size
    assert_equal 'host1', records.first[:host]
  end

  def test_create_record
    params = {:host => 'newhost', :domain => 'example1.com', :data => '1.1.1.1', :type => 'A', :ttl => '333'}
    dest_params = {'hostname' => 'newhost', 'data' => '1.1.1.1', 'host_type' => 'A', 'ttl' => '333', :zone_id => @zone.id}

    ::Zerigo::DNS::Host.expects(:create).with(dest_params)
    
    @dns.create_host_record(params)
  end

  def test_destroy_record
    params = {:host => 'host1', :domain => 'example1.com'}

    FakeWeb.register_uri(:get,
                         "https://foo%40bar.com:testtoken@ns.zerigo.com/api/1.1/hosts.xml?fqdn=host1.example1.com&zone_id=1",
                         :body => fakeweb_fixture('zerigo/host1.xml'))
    FakeWeb.register_uri(:delete,
                         "https://foo%40bar.com:testtoken@ns.zerigo.com/api/1.1/hosts/1.xml",
                         :body => "")

    @dns.destroy_host_record(params)
  end

  def test_update_record
    params = {:host => 'host1', :domain => 'example1.com', :data => "1.1.1.1"}
    new = {:host => 'host1', :domain => 'example1.com', :data => "1.1.1.2"}

    FakeWeb.register_uri(:get,
                         "https://foo%40bar.com:testtoken@ns.zerigo.com/api/1.1/hosts.xml?fqdn=host1.example1.com&zone_id=1",
                         :body => fakeweb_fixture('zerigo/host1.xml'))
    FakeWeb.register_uri(:post,
                         "https://foo%40bar.com:testtoken@ns.zerigo.com/api/1.1/hosts/1.xml",
                         :body => "")

    @dns.update_host_record(params, new)
  end

end
