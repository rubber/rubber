require_relative '../test_helper'

class Rubber::Configuration::FileConfigurationStorageTest < Test::Unit::TestCase
  include Rubber::Configuration

  setup do
    @tmpdir = Dir.mktmpdir
    @config_file = File.join(@tmpdir, "instance-test.yml")

    @items = {}
    @artifacts = {}

    @cluster = stub items: @items, artifacts: @artifacts
    @storage = FileConfigurationStorage.new @cluster, @config_file
  end

  teardown do
    FileUtils.remove_entry_secure @tmpdir
  end

  should "indicate that it's stored locally" do
    assert @storage.stored_locally?
  end

  should "load configuration from a file" do
    FileUtils.cp fixture_file("configuration/instance-test.yml"), @config_file
    @storage.load

    assert_equal 1, @cluster.items.length
    assert @cluster.items.key?("app01")
    assert @cluster.items["app01"].is_a?(InstanceItem)
    assert @cluster.artifacts.key?("volumes")
    assert @cluster.artifacts["volumes"].key?("app01_/dev/sdi")
    assert_equal "vol-deadbeef", @cluster.artifacts["volumes"]["app01_/dev/sdi"]
  end

  should "save configuration to a file" do
    @cluster.items["app01"] = InstanceItem.new "app01", "rubber.test", nil, nil, nil, nil
    @cluster.artifacts["volumes"] = {
      "app01_/dev/sdi" => "vol-deadbeef"
    }

    @storage.save

    assert File.exist?(@config_file)

    loaded = YAML.load_file @config_file

    assert_equal 2, loaded.length
    assert loaded.first.is_a?(InstanceItem)
    assert_equal "app01", loaded.first.name
    assert_equal "rubber.test", loaded.first.domain

    assert loaded.last.key?("volumes")
    assert loaded.last["volumes"].key?("app01_/dev/sdi")
    assert_equal "vol-deadbeef", loaded.last["volumes"]["app01_/dev/sdi"]
  end
end
