require_relative '../test_helper'
require 'rubber/cloud/aws'
require 'rubber/cloud/aws/vpc'

class Rubber::Configuration::S3ConfigurationStorageTest < Test::Unit::TestCase
  include Rubber::Configuration

  setup do
    @bucket = "s3-configuration-storage-test"
    @key = "foo/cluster-test.yml"

    stub_rubber_storage

    # Fog.mock! is called in test_helper.rb so this won't affect any real
    # cloud data
    Rubber.cloud.storage(@bucket).ensure_bucket

    @items = {}
    @artifacts = {}

    @cluster = stub items: @items, artifacts: @artifacts
    @storage = S3ConfigurationStorage.new @cluster, File.join(@bucket, @key)
  end

  should "not indicate that it's stored locally" do
    assert !@storage.stored_locally?
  end

  should "load configuration from an s3 object" do
    Rubber.cloud.storage(@bucket).store(
      @key,
      File.read(fixture_file("configuration/cluster-test.yml"))
    )
    @storage.load

    assert_equal 1, @cluster.items.length
    assert @cluster.items.key?("app01")
    assert @cluster.items["app01"].is_a?(Server)
    assert @cluster.artifacts.key?("volumes")
    assert @cluster.artifacts["volumes"].key?("app01_/dev/sdi")
    assert_equal "vol-deadbeef", @cluster.artifacts["volumes"]["app01_/dev/sdi"]
  end

  should "load a legacy configuration from an s3 object" do
    Rubber.cloud.storage(@bucket).store(
      @key,
      File.read(fixture_file("configuration_legacy/instance-test.yml"))
    )
    @storage.load

    assert_equal 1, @cluster.items.length
    assert @cluster.items.key?("app01")
    assert @cluster.items["app01"].is_a?(Server)
    assert @cluster.artifacts.key?("volumes")
    assert @cluster.artifacts["volumes"].key?("app01_/dev/sdi")
    assert_equal "vol-deadbeef", @cluster.artifacts["volumes"]["app01_/dev/sdi"]
  end

  should "save configuration to an s3 object" do
    @cluster.items["app01"] = Server.new "app01", "rubber.test", nil, nil, nil, nil
    @cluster.artifacts["volumes"] = {
      "app01_/dev/sdi" => "vol-deadbeef"
    }

    @storage.save

    stored_data = Rubber.cloud.storage(@bucket).fetch(@key)
    assert stored_data, "Expected data to be written to (mocked) s3 bucket"

    loaded = YAML.parse(stored_data).to_ruby

    assert_equal 2, loaded.length

    assert loaded.first.is_a?(Server)
    assert_equal "app01", loaded.first.name
    assert_equal "rubber.test", loaded.first.domain

    assert loaded.last.key?("volumes")
    assert loaded.last["volumes"].key?("app01_/dev/sdi")
    assert_equal "vol-deadbeef", loaded.last["volumes"]["app01_/dev/sdi"]
  end

  private

  def stub_rubber_storage
    fake_env = {}

    def fake_env.access_key
      "abc123"
    end

    def fake_env.secret_access_key
      "secret"
    end

    def fake_env.region
      "us-east-1"
    end

    def fake_env.compute_credentials
      self["compute_credentials"]
    end

    def fake_env.storage_credentials
      self["storage_credentials"]
    end

    fake_cloud = Rubber::Cloud::Aws::Vpc.new fake_env, mock('capistrano')

    Rubber.stubs(:cloud).returns(fake_cloud)
  end
end
