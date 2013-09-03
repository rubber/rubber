require File.expand_path(File.join(__FILE__, '../..', 'test_helper'))
require 'rubber/cloud/digital_ocean'
require 'ostruct'

class DigitalOceanTest < Test::Unit::TestCase

  context 'digital_ocean' do

    setup do
      env = {'client_key' => "XXX", 'api_key' => "YYY", 'region' => 'New York 1', 'key_file' => "#{File.dirname(__FILE__)}/../fixtures/basic/test.pem"}
      env = Rubber::Configuration::Environment::BoundEnv.new(env, nil, nil, nil)
      @cloud = Rubber::Cloud::DigitalOcean.new(env, nil)
    end

    should 'instantiate' do
      assert @cloud.compute_provider
      assert_nil @cloud.storage_provider
    end

    context '#create_instance' do
      should 'create instance' do
        assert @cloud.create_instance('my-instance', 'Ubuntu 12.04 x64', '512MB', [], '', 'New York 1')
      end

      should 'raise error if invalid region' do
        begin
          @cloud.create_instance('my-instance', 'Ubuntu 12.04 x64', '512MB', [], '', 'Mars 1')
        rescue => e
          assert_equal 'Invalid region for DigitalOcean: Mars 1', e.message
        else
          fail 'Did not raise exception for invalid region'
        end
      end

      should 'raise an error if invalid image type' do
        begin
          @cloud.create_instance('my-instance', 'Ubuntu 12.04 x64', 'm1.small', [], '', 'New York 1')
        rescue => e
          assert_equal 'Invalid image type for DigitalOcean: m1.small', e.message
        else
          fail 'Did not raise exception for invalid image type'
        end
      end

      should 'raise an error if invalid image name' do
        begin
          @cloud.create_instance('my-instance', 'Windows Server 2003', '512MB', [], '', 'New York 1')
        rescue => e
          assert_equal 'Invalid image name for DigitalOcean: Windows Server 2003', e.message
        else
          fail 'Did not raise exception for invalid image name'
        end
      end

      should 'raise an error if no remote SSH key and local key_file is bad' do
        begin
          env = {'client_key' => "XXX", 'api_key' => "YYY", 'region' => 'New York 1'}
          env = Rubber::Configuration::Environment::BoundEnv.new(env, nil, nil, nil)
          cloud = Rubber::Cloud::DigitalOcean.new(env, nil)

          cloud.create_instance('my-instance', 'Ubuntu 12.04 x64', '512MB', [], '', 'New York 1')
        rescue => e
          assert_equal 'Missing key_file for DigitalOcean', e.message
        else
          fail 'Did not raise exception for missing key_file'
        end
      end
    end
  end
end
