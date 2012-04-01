require File.expand_path(File.join(__FILE__, '../..', 'test_helper'))
require 'rubber/dns/fog'
#require 'rexml/document'

class FogTest < Test::Unit::TestCase

  @envs = []
  
  env = {'credentials' =>
            {'provider' => 'zerigo', 'zerigo_email' => 'xxx', 'zerigo_token' => 'yyy'}}
  @envs << Rubber::Configuration::Environment::BoundEnv.new(env, nil, nil)

  # no mocks for aws dns yet
  #env = {'credentials' =>
  #          {'provider' => 'aws', 'aws_access_key_id' => 'xxx', 'aws_secret_access_key' => 'yyy'}}
  #@envs << Rubber::Configuration::Environment::BoundEnv.new(env, nil, nil)
  
  
  @envs.each do |env|
  
  context "fog #{env.credentials.provider} dns" do
    
    setup do
      @env = env
    end
    
    context "find_or_create" do
      
      should "create domain if it doesn't exist" do
        @dns = Rubber::Dns::Fog.new(@env)
    
        assert_equal 0, @dns.client.zones.all.size
        
        zone0 = @dns.find_or_create_zone("example1.com")
        
        assert_equal 1, @dns.client.zones.all.size
        zone1 = @dns.client.zones.all.find {|z| z.domain =~ /^example1.com/ }
        assert zone1
        assert_equal zone0.id, zone1.id
        assert_equal zone0.domain, zone1.domain
      end
      
      should "match the same domain that was passed" do
        @dns = Rubber::Dns::Fog.new(@env)
    
        assert_equal 0, @dns.client.zones.all.size
        
        zone0 = @dns.find_or_create_zone("abcfoo.com")
        zone1 = @dns.find_or_create_zone("foo.com")
        
        assert_equal 2, @dns.client.zones.all.size
        
        zone2 = @dns.client.zones.all.find {|z| z.domain =~ /^foo.com/ }
        assert zone2
        assert_equal zone1.id, zone2.id
        assert_equal zone1.domain, zone2.domain
      end
      
      should "do nothing if domain already exists" do
        @dns = Rubber::Dns::Fog.new(@env)
        
        @dns.client.zones.create(:domain => 'example1.com')
        assert_equal 1, @dns.client.zones.all.size
        
        zone0 = @dns.find_or_create_zone("example1.com")
        
        assert_equal 1, @dns.client.zones.all.size
        zone1 = @dns.client.zones.all.find {|z| z.domain =~ /^example1.com/ }
        assert_equal zone0.id, zone1.id
        assert_equal zone0.domain, zone1.domain
      end
      
    end
    
    context "records" do
  
      setup do
        @dns = Rubber::Dns::Fog.new(@env)
      
        @domain = "example1.com"
        @zone = @dns.find_or_create_zone(@domain)
      end
          
      should "find_records" do
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
      
      should "create_record" do
        @dns.create_host_record({:host => 'newhost', :domain => @domain, :data => '1.1.1.1', :type => 'A', :ttl => '333'})
      
        assert_equal @zone.records.all.size, 1
        record = @zone.records.first
      
        assert_equal 'newhost',             record.name
        assert_equal "newhost.#{@domain}",  record.domain
        assert_equal '1.1.1.1',             record.value
        assert_equal 'A',                   record.type
        assert_equal 333,                   record.ttl
      end
      
      should "destroy_record" do
        # Create the record we want to test destroying.
        @zone.records.create(:type => 'A', :value => '172.16.16.1', :name => 'host1', :domain => @domain)
        assert_equal 1, @zone.records.all.size
      
        @dns.destroy_host_record({:host => 'host1', :domain => @domain})
      
        assert_equal 0, @zone.records.all.size
      end
      
      should "update_record" do
        params = {:host => 'host1', :domain => @domain, :data => "1.1.1.1"}
        new = {:host => 'host1', :domain => @domain, :data => "1.1.1.2"}
      
        @zone.records.create(:type => 'A', :value => '1.1.1.1', :name => 'host1', :domain => @domain)
      
        @dns.update_host_record(params, new)
      
        record = @zone.records.all.first
        assert_equal '1.1.1.2', record.value
      end

    end
    
  end
    
  end
end
