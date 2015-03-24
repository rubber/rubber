require File.expand_path(File.join(__FILE__, '../..', 'test_helper'))
require 'rubber/cloud/datto'
require 'vcr'
require 'webmock'

# NOTE: Must re-record one at a time for any test that invokes create_instance.
# This is true until we allow povisioning arbitrarily, or if you expect the instances list to
# be empty.
class DattoTest < Test::Unit::TestCase
  context 'datto' do
    setup do
      WebMock.enable!

      VCR.configure do |config|
        config.cassette_library_dir = "test/fixtures/vcr_cassettes"
        config.hook_into :webmock
      end

      env = {
        'endpoint' => '10.30.95.138',
      }

      env = Rubber::Configuration::Environment::BoundEnv.new(env, nil, nil, nil)
      @cloud = Rubber::Cloud::Datto.new(env, nil)
    end

    teardown do
      WebMock.disable!
    end

    should 'create instance' do
      ::VCR.use_cassette("datto/create_instance") do
        assert @cloud.create_instance('', '', '', '', '', '')
      end
    end

    context 'describe_instances' do
      should 'be able to describe all instances if no instance id is provided' do
        ::VCR.use_cassette("datto/describe_all_instances") do
          # create an instance
          assert @cloud.create_instance('', '', '', '', '', '')

          instances = @cloud.describe_instances
          assert_equal 1, instances.count
        end
      end

      should 'return empty array if no instances' do
        ::VCR.use_cassette("datto/describe_instance/no_instances") do
          assert @cloud.describe_instances.empty?
        end
      end

      # Current behaviour not sure if this is what we want long term.
      should 'error if the provided instance id does not exist' do
        ::VCR.use_cassette("datto/describe_instance/does_not_exist") do
          exception = assert_raises(StandardError)do
            assert @cloud.describe_instances("0000")
          end
          assert "Worker 0000 doesn't exist", exception.message
        end
      end

      should 'return just information about the requested instance' do
        ::VCR.use_cassette('datto/describe_instance/single_instance') do
          # create an instance
          instance_id = @cloud.create_instance('', '', '', '', '', '')

          instances = @cloud.describe_instances

          assert_equal Integer(instance_id, 10), instances.first[:id]
        end
      end
    end
  end
end
