require File.expand_path(File.join(__FILE__, '../..', 'test_helper'))
require 'rubber/dns/fog'

class FogTest < Test::Unit::TestCase

  @envs = []

  env = {'credentials' =>
             {'provider' => 'zerigo', 'zerigo_email' => 'xxx', 'zerigo_token' => 'yyy'}}
  @envs << Rubber::Configuration::Environment::BoundEnv.new(env, nil, nil)

  unless ENV['CI']
    secret = YAML.load_file(File.expand_path("~/rubber-secret.yml")) rescue {}
    access_key = secret['cloud_providers']['aws']['access_key']
    access_secret = secret['cloud_providers']['aws']['secret_access_key']
    env = {'credentials' =>
               {'provider' => 'aws', 'aws_access_key_id' => access_key, 'aws_secret_access_key' => access_secret},
           'name_includes_domain' => true,
           'name_includes_trailing_period' => true}
    # no mocks for aws dns yet
    @envs << Rubber::Configuration::Environment::BoundEnv.new(env, nil, nil)
  end

  def all_test_zones(dns=@dns)
    dns.client.zones.all.find_all {|z| z.domain =~ /rubbertest/ }
  end
  
  def destroy_test_domains
    all_test_zones(Rubber::Dns::Fog.new(@env)).each do |zone|
      zone.records.all.each do |record|
        record.destroy
      end
      zone.destroy
    end
  end
  
  env = @envs.first
  @envs.each do |env|

    context "fog #{env.credentials.provider} dns" do

      setup do
        @env = env

        # no mocks for aws dns yet
        if env.credentials.provider == 'aws'
          Fog.unmock!
          destroy_test_domains
        end
        
        @dns = Rubber::Dns::Fog.new(@env)
      end
      
      context "find_or_create" do
      
        should "create domain if it doesn't exist" do
          assert_equal 0, all_test_zones.size
      
          zone0 = @dns.find_or_create_zone("rubbertest.com")
      
          assert_equal 1, all_test_zones.size
          zone1 = all_test_zones.find {|z| z.domain =~ /^rubbertest.com/ }
          assert zone1
          assert_equal zone0.id, zone1.id
          assert_equal zone0.domain, zone1.domain
        end
      
        should "match the same domain that was passed" do
          assert_equal 0, all_test_zones.size
      
          zone0 = @dns.find_or_create_zone("abcrubbertest.com")
          zone1 = @dns.find_or_create_zone("rubbertest.com")
      
          assert_equal 2, all_test_zones.size
      
          zone2 = all_test_zones.find {|z| z.domain =~ /^rubbertest.com/ }
          assert zone2
          assert_equal zone1.id, zone2.id
          assert_equal zone1.domain, zone2.domain
        end
      
        should "do nothing if domain already exists" do
          @dns.client.zones.create(:domain => 'rubbertest.com')
          assert_equal 1, all_test_zones.size
      
          zone0 = @dns.find_or_create_zone("rubbertest.com")
      
          assert_equal 1, all_test_zones.size
          zone1 = all_test_zones.find {|z| z.domain =~ /^rubbertest.com/ }
          assert_equal zone0.id, zone1.id
          assert_equal zone0.domain, zone1.domain
        end
      
      end

      context "records" do
      
        setup do
          @domain = "rubbertest.com"
          @zone = @dns.find_or_create_zone(@domain)
        end
      
        should "create_record" do
          @dns.create_host_record({:host => 'newhost', :domain => @domain, :data => '1.1.1.1', :type => 'A', :ttl => '333'})
        
          assert_equal @zone.records.all.size, 1
          record = @zone.records.first
          attributes = @dns.host_to_opts(record)
        
          assert_equal 'newhost',             attributes[:host]
          assert_equal @domain,               attributes[:domain]
          assert_equal '1.1.1.1',             attributes[:data]
          assert_equal 'A',                   attributes[:type]
          assert_equal 333,                   attributes[:ttl]
        end
        
        should "destroy_record" do
          # Create the record we want to test destroying.
          @dns.create_host_record({:host => 'newhost', :domain => @domain, :data => '1.1.1.1', :type => 'A'})
          assert_equal 1, @zone.records.all.size
        
          @dns.destroy_host_record({:host => 'newhost', :domain => @domain})
        
          assert_equal 0, @zone.records.all.size
        end
        
        should "update_record" do
          params = {:host => 'host1', :domain => @domain, :data => "1.1.1.1"}
          new = {:host => 'host1', :domain => @domain, :data => "1.1.1.2"}
        
          @dns.create_host_record({:host => 'host1', :domain => @domain, :data => '1.1.1.1', :type => 'A'})
          assert_equal 1, @zone.records.all.size
        
          @dns.update_host_record(params, new)
          assert_equal 1, @zone.records.all.size
        
          record = @zone.records.all.first
          attributes = @dns.host_to_opts(record)
          assert_equal '1.1.1.2', attributes[:data]
        end
        
        should "find_records" do
          # Set up some sample records.
          created = []
          created << {:host => 'host1', :domain => @domain, :data => '1.1.1.1', :type => 'A'}
          created << {:host => '', :domain => @domain, :data => '1.1.1.1', :type => 'A'}
          created.each {|r| @dns.create_host_record(r) }
        
          # Search for records through the rubber DNS interface and make sure whe get what we expected.
        
          # Wildcard search.
          records = @dns.find_host_records(:host => '*', :domain => @domain)
          assert_equal 2, records.size
        
          # Blank hostname search.
          records = @dns.find_host_records(:host => '', :domain => @domain)
          assert_equal 1, records.size
          assert_equal '', records.first[:host]
        
          # Specific hostname search.
          records = @dns.find_host_records(:host => 'host1', :domain => @domain)
          assert_equal 1, records.size
          assert_equal 'host1', records.first[:host]
        end
      
      end

    end

  end
end
