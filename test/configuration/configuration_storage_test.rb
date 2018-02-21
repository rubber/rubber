require_relative '../test_helper'

class Rubber::Configuration::ConfigurationStorageTest < Test::Unit::TestCase
  include Rubber::Configuration

  context ".for_cluster_from_storage_string" do
    setup do
      @cluster = mock('cluster')
    end

    should "retain the passed cluster" do
      storage = ConfigurationStorage.for_cluster_from_storage_string(
        @cluster,
        'file:/tmp/foo'
      )

      assert_equal @cluster, storage.cluster
    end

    should "retain the path from the passed uri" do
      storage = ConfigurationStorage.for_cluster_from_storage_string(
        @cluster,
        'file:/tmp/foo'
      )

      assert_equal "/tmp/foo", storage.path
    end

    should "return a FileConfigurationStorage" do
      storage = ConfigurationStorage.for_cluster_from_storage_string(
        @cluster,
        'file:/tmp/foo'
      )

      assert storage.is_a?(FileConfigurationStorage)
    end

    should "return an S3ConfigurationStorage" do
      storage = ConfigurationStorage.for_cluster_from_storage_string(
        @cluster,
        'storage:tmp/foo/bar'
      )

      assert storage.is_a?(S3ConfigurationStorage)
      assert_equal "tmp", storage.bucket
      assert_equal "foo/bar", storage.key
    end

    should "return a TableConfigurationstorage" do
      storage = ConfigurationStorage.for_cluster_from_storage_string(
        @cluster,
        'table:foo'
      )

      assert storage.is_a?(TableConfigurationStorage)
      assert_equal "foo", storage.table_key
    end

    should "raise an exception if an invalid uri is given" do
      exception = assert_raises do
        ConfigurationStorage.for_cluster_from_storage_string(
          @cluster,
          "invalid:/foo/bar"
        )
      end

      assert_equal "Invalid configuration_storage string: invalid:/foo/bar\nMust be one of file:, table:, storage:",
                   exception.message
    end
  end
end
