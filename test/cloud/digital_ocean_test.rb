require File.expand_path(File.join(__FILE__, '../..', 'test_helper'))
require 'rubber/cloud/digital_ocean'
require 'ostruct'

class DigitalOceanTest < Test::Unit::TestCase

  context 'digital_ocean' do

    setup do
      env = {
        'digital_ocean_token' => "XYZ",
        'region' => 'nyc1',
        'key_file' => "#{File.dirname(__FILE__)}/../fixtures/basic/test.pem",
        'key_name' => 'test'
      }
      env = Rubber::Configuration::Environment::BoundEnv.new(env, nil, nil, nil)
      @cloud = Rubber::Cloud::DigitalOcean.new(env, nil)

      @cloud.compute_provider.ssh_keys.each do |key|
        @cloud.compute_provider.delete_ssh_key(key.id)
      end

      # This is currently (as of 11/2/15) the only valid image name in
      # Fog's mocked digital ocean images request
      @valid_image_name = "Nifty New Snapshot"
    end

    should 'instantiate' do
      assert @cloud.compute_provider
      assert_nil @cloud.storage_provider
    end

    context '#create_instance' do
      should 'create instance' do
        assert @cloud.create_instance('my-instance', @valid_image_name, '512MB', [], '', 'nyc1')
      end

      should 'create instance with private networking enabled' do
        env = {
          'digital_ocean_token' => "XYZ",
          'key_file' => "#{File.dirname(__FILE__)}/../fixtures/basic/test.pem",
          'key_name' => 'test',
          'private_networking' => true
        }

        env = Rubber::Configuration::Environment::BoundEnv.new(env, nil, nil, nil)

        assert Rubber::Cloud::DigitalOcean.new(env, nil).create_instance('my-instance', @valid_image_name, '512MB', [], '', 'nyc2')
      end

      should 'raise error if region does not support private networking but private networking is enabled' do
        env = {
          'digital_ocean_token' => "XYZ",
          'key_file' => "#{File.dirname(__FILE__)}/../fixtures/basic/test.pem",
          'key_name' => 'test',
          'private_networking' => true
        }

        env = Rubber::Configuration::Environment::BoundEnv.new(env, nil, nil, nil)

        begin
          Rubber::Cloud::DigitalOcean.new(env, nil).create_instance('my-instance', @valid_image_name, '512MB', [], '', 'nyc1')
        rescue => e
          assert_equal 'Private networking is enabled, but region nyc1 does not support it', e.message
        else
          fail 'Did not raise exception for region that does not support private networking'
        end
      end

      should 'raise error if invalid region' do
        begin
          @cloud.create_instance('my-instance', @valid_image_name, '512MB', [], '', 'mars1')
        rescue => e
          assert_equal 'Invalid region for DigitalOcean: mars1', e.message
        else
          fail 'Did not raise exception for invalid region'
        end
      end

      should 'raise an error if invalid image type' do
        begin
          @cloud.create_instance('my-instance', @valid_image_name, 'm1.small', [], '', 'nyc1')
        rescue => e
          assert_equal 'Invalid image type for DigitalOcean: m1.small', e.message
        else
          fail 'Did not raise exception for invalid image type'
        end
      end

      should 'raise an error if invalid image name' do
        begin
          @cloud.create_instance('my-instance', 'Windows Server 2003', '512MB', [], '', 'nyc1')
        rescue => e
          assert_equal 'Invalid image name for DigitalOcean: Windows Server 2003', e.message
        else
          fail 'Did not raise exception for invalid image name'
        end
      end

      should 'raise an error if no remote SSH key and local key_file is bad' do
        begin
          env = {
            'digital_ocean_token' => "XYZ",
            'region' => 'nyc1',
            'key_name' => 'test'
          }
          env = Rubber::Configuration::Environment::BoundEnv.new(env, nil, nil, nil)
          cloud = Rubber::Cloud::DigitalOcean.new(env, nil)

          cloud.create_instance('my-instance', @valid_image_name, '512MB', [], '', 'New York 1')
        rescue => e
          assert_equal 'Missing key_file for DigitalOcean', e.message
        else
          fail 'Did not raise exception for missing key_file'
        end
      end
    end
  end

  context 'digital ocean with aws storage' do

    setup do
      env = {
        'digital_ocean_token' => "xyz",
        'region' => 'nyc1',
        'key_file' => "#{File.dirname(__FILE__)}/../fixtures/basic/test.pem",
        'key_name' => 'test'
      }

      @aws_region = "ap-southeast-2"
      env['cloud_providers'] = {'aws' => {'access_key' => "XXX", 'secret_access_key' => "YYY", 'region' => @aws_region}}
      env = Rubber::Configuration::Environment::BoundEnv.new(env, nil, nil, nil)
      @cloud = Rubber::Cloud::DigitalOcean.new(env, nil)
    end

    should 'set the region on the aws storage provider' do
      assert_equal @cloud.storage_provider.region, @aws_region
    end
  end
end
