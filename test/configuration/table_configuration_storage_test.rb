require_relative '../test_helper'
require 'rubber/cloud/aws'
require 'rubber/cloud/aws/vpc'

class Rubber::Configuration::TableConfigurationStorageTest < Test::Unit::TestCase
  include Rubber::Configuration

  setup do
    @key = "table_configuration_storage_test/instance-test"

    stub_rubber_storage

    # Fog.mock! is called in test_helper.rb so this won't affect any real
    # cloud data
    Rubber.cloud.table_store(@key).ensure_table_key

    # Fog doesn't have a mock implementation for SimpleDB select yet
    stub_simple_db_select

    @items = {}
    @artifacts = {}

    @cluster = stub items: @items, artifacts: @artifacts
    @storage = TableConfigurationStorage.new @cluster, @key
  end

  should "load configuration from a SimpleDB table" do
    fixture_file_array.each do |node|
      if node.is_a?(InstanceItem)
        Rubber.cloud.table_store(@key).put(node.name, node.to_hash)
      else
        Rubber.cloud.table_store(@key).put("_artifacts", node)
      end
    end

    @storage.load

    assert_equal 1, @cluster.items.length
    assert @cluster.items.key?("app01")
    assert @cluster.items["app01"].is_a?(InstanceItem)
    assert @cluster.artifacts.key?("volumes")
    assert @cluster.artifacts["volumes"].key?("app01_/dev/sdi")
    assert_equal "vol-deadbeef", @cluster.artifacts["volumes"]["app01_/dev/sdi"]
  end

  should "save configuration to a SimpleDB table" do
    @cluster.items["app01"] = InstanceItem.new "app01",
                                               "rubber.test",
                                               [RoleItem.new("app")],
                                               "i-deadbeef",
                                               "t2.medium",
                                               "ami-deadbeef"
    @cluster.artifacts["volumes"] = {
      "app01_/dev/sdi" => "vol-deadbeef"
    }

    @storage.save

    instance_data = Rubber.cloud.table_store(@key).get("app01")
    assert instance_data, "Expected instance data to be written to (mocked) SimpleDB table"

    assert_equal "app01", instance_data['name']
    assert_equal "rubber.test", instance_data['domain']

    artifact_data = Rubber.cloud.table_store(@key).get("_artifacts_")

    assert artifact_data, "Expected artifact data to be written to (mocked) SimpleDB table"
    assert artifact_data.key?("volumes")
    assert artifact_data["volumes"].key?("app01_/dev/sdi")
    assert_equal "vol-deadbeef", artifact_data["volumes"]["app01_/dev/sdi"]
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

  def stub_simple_db_select
    response_data =  {
      "app01" => {
        "name" => [["app01"].to_json],
        "domain" => [["rubber.test"].to_json]
      },
      "_artifacts_" => {
        "volumes" => [
          [{ "app01_/dev/sdi" => "vol-deadbeef" }].to_json
        ]
      }
    }

    fake_response = mock('response')
    fake_response
      .expects(:body)
      .twice
      .returns(({
                  'Items' => response_data
                }))

    Rubber.cloud
      .send(:instance_variable_get, :@table_store)
      .expects(:select)
      .returns(fake_response)
  end

  def fixture_file_array
    YAML.parse(File.read(fixture_file("configuration/instance-test.yml"))).to_ruby
  end
end
