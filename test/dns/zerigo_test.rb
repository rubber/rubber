require File.expand_path(File.join(__FILE__, '../..', 'test_helper'))
require 'rubber/dns/zerigo'

class ZerigoTest < Test::Unit::TestCase

# This entire test is disabled because the Zerigo mocks in fog are utterly broken, currently.  The following fix
# needs to be made upstream before these will run again:
# https://github.com/fog/fog/commit/6f8c0e61201f1f46d568f8e1ebbc1aa0e2c65d32

=begin
   context "fog zerigo dns" do

      setup do
        env = {'email' => get_secret('dns_providers.zerigo.email') || 'xxx',
               'token' => get_secret('dns_providers.zerigo.token') || 'yyy'}
        @env = Rubber::Configuration::Environment::BoundEnv.new(env, nil, nil, nil)

        @dns = Rubber::Dns::Zerigo.new(@env)
        destroy_test_domains(@dns)
      end

      context "compatibility" do
        should "create using old credential style" do
          env = {'dns_provider' => 'fog',
                 'dns_providers' => {
                     'fog' => {
                         'credentials' => {
                            'provider' => 'zerigo', 'zerigo_email' => 'xxx', 'zerigo_token' => 'yyy'
                         }
                     }
                 }
          }
          @env = Rubber::Configuration::Environment::BoundEnv.new(env, nil, nil, nil)
          
          provider = Rubber::Dns::get_provider(@env.dns_provider, @env)
          assert provider
          assert provider.instance_of?(Rubber::Dns::Zerigo)
        end
      end
      
      context "find_or_create" do
      
        should "create domain if it doesn't exist" do
          assert_equal 0, all_test_zones(@dns).size
                
          zone0 = @dns.find_or_create_zone("#{TEST_DOMAIN}1.com")
      
          assert_equal 1, all_test_zones(@dns).size
          zone1 = all_test_zones(@dns).find {|z| z.domain =~ /^#{TEST_DOMAIN}1.com/ }
          assert zone1
          assert_equal zone0.id, zone1.id
          assert_equal zone0.domain, zone1.domain
        end
      
        should "match the same domain that was passed" do
          assert_equal 0, all_test_zones(@dns).size
      
          zone0 = @dns.find_or_create_zone("abc#{TEST_DOMAIN}2.com")
          zone1 = @dns.find_or_create_zone("#{TEST_DOMAIN}2.com")
      
          assert_equal 2, all_test_zones(@dns).size
      
          zone2 = all_test_zones(@dns).find {|z| z.domain =~ /^#{TEST_DOMAIN}2.com/ }
          assert zone2
          assert_equal zone1.id, zone2.id
          assert_equal zone1.domain, zone2.domain
        end
      
        should "do nothing if domain already exists" do
          @dns.client.zones.create(:domain => "#{TEST_DOMAIN}3.com")
          assert_equal 1, all_test_zones(@dns).size
      
          zone0 = @dns.find_or_create_zone("#{TEST_DOMAIN}3.com")
      
          assert_equal 1, all_test_zones(@dns).size
          zone1 = all_test_zones(@dns).find {|z| z.domain =~ /^#{TEST_DOMAIN}3.com/ }
          assert_equal zone0.id, zone1.id
          assert_equal zone0.domain, zone1.domain
        end
      
      end

      context "records" do
      
        setup do
          @domain = "#{TEST_DOMAIN}#{rand(90) + 10}.com"
          @zone = @dns.find_or_create_zone(@domain)
        end
      
        should "create_record" do
          @dns.create_host_record({:host => 'newhost', :domain => @domain, :data => ['1.1.1.1'], :type => 'A', :ttl => '333'})
        
          assert_equal @zone.records.all.size, 1
          record = @zone.records.first
          attributes = @dns.hosts_to_opts([record])
        
          assert_equal 'newhost',             attributes[:host]
          assert_equal @domain,               attributes[:domain]
          assert_equal ['1.1.1.1'],             attributes[:data]
          assert_equal 'A',                   attributes[:type]
          assert_equal 333,                   attributes[:ttl]
        end
        
        should "destroy_record" do
          # Create the record we want to test destroying.
          @dns.create_host_record({:host => 'newhost', :domain => @domain, :data => ['1.1.1.1'], :type => 'A'})
          assert_equal 1, @zone.records.all.size
        
          @dns.destroy_host_record({:host => 'newhost', :domain => @domain})
        
          assert_equal 0, @zone.records.all.size
        end
        
        should "update_record" do
          params = {:host => 'host1', :domain => @domain, :data => ["1.1.1.1"]}
          new = {:host => 'host1', :domain => @domain, :data => ["1.1.1.2"]}
        
          @dns.create_host_record({:host => 'host1', :domain => @domain, :data => ['1.1.1.1'], :type => 'A'})
          assert_equal 1, @zone.records.all.size
        
          @dns.update_host_record(params, new)
          assert_equal 1, @zone.records.all.size
        
          record = @zone.records.all.first
          attributes = @dns.hosts_to_opts([record])
          assert_equal ['1.1.1.2'], attributes[:data]
        end
        
        should "find no records" do
          # Wildcard search.
          records = @dns.find_host_records(:host => 'foo', :domain => @domain)
          assert_equal 0, records.size
        end
      
        should "find_records" do
          # Set up some sample records.
          created = []
          created << {:host => 'host1', :domain => @domain, :data => ['1.1.1.1'], :type => 'A'}
          created << {:host => '', :domain => @domain, :data => ['1.1.1.1'], :type => 'A'}
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
      
        should "find_many_records" do
          omit "fog-zerigo implementation doesn't support pagination" if ENV['NO_FOG_MOCK']
          
          # Set up many sample records - more than the max returned
          # in a single fetch so we can test pagination
          max = 302
          created = []
          max.times do |i|
            created << {:host => "host#{i}", :domain => @domain, :data => ['1.1.1.1'], :type => 'A'}
          end
          created.each {|r| @dns.create_host_record(r) }
          
          # Search for records through the rubber DNS interface and make sure whe get what we expected.
        
          # Wildcard search.
          records = @dns.find_host_records(:host => '*', :domain => @domain)
          assert_equal max, records.size
        
          # Specific hostname search.
          records = @dns.find_host_records(:host => 'host1', :domain => @domain)
          assert_equal 1, records.size
          assert_equal 'host1', records.first[:host]

          # Specific hostname search.
          records = @dns.find_host_records(:host => "host#{max - 1}", :domain => @domain)
          assert_equal 1, records.size
          assert_equal "host#{max - 1}", records.first[:host]
        end
      
      end

   end
=end
end
