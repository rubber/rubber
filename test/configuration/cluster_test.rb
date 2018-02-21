require_relative '../test_helper'

require 'rubber/configuration/cluster'

class Rubber::Configuration::ClusterTest < Test::Unit::TestCase
  include Rubber::Configuration

  def instance_setup
    @instance = Cluster.new("file:#{Tempfile.new('testforrole').path}")
    @instance.add(@i1 = InstanceItem.new('host1', 'domain.com', [RoleItem.new('role1')], '', 'm1.small', 'ami-7000f019'))
    @instance.add(@i2 = InstanceItem.new('host2', 'domain.com', [RoleItem.new('role1')], '', 'm1.small', 'ami-7000f019'))
    @instance.add(@i3 = InstanceItem.new('host3', 'domain.com', [RoleItem.new('role2')], '', 'm1.small', 'ami-7000f019'))
    @instance.add(@i4 = InstanceItem.new('host4', 'domain.com', [RoleItem.new('role2', 'primary' => true)], '', 'm1.small', 'ami-7000f019'))
  end

  context "instance" do
    setup do
      instance_setup
    end

    context "for_role" do

      should "give the right instances for selected role" do
        assert_equal 2, @instance.for_role('role1').size, 'not finding correct instances for role'
        assert_equal 2, @instance.for_role('role2').size, 'not finding correct instances for role'
        assert_equal 1, @instance.for_role('role2', {}).size, 'not finding correct instances for role'
        assert_equal @i3, @instance.for_role('role2', {}).first, 'not finding correct instances for role'
        assert_equal 1, @instance.for_role('role2', 'primary' => true).size, 'not finding correct instances for role'
        assert_equal @i4, @instance.for_role('role2', 'primary' => true).first, 'not finding correct instances for role'
      end

    end

    context "filtering" do

      should "not filter for empty FILTER(_ROLES)" do
        ENV['FILTER'] = nil
        ENV['FILTER_ROLES'] = nil
        instance_setup
        assert_equal 4, @instance.filtered().size
      end


      should "filter hosts" do
        ENV['FILTER_ROLES'] = nil
        ENV['FILTER'] = 'host1'
        instance_setup
        assert_equal [@i1].sort, @instance.filtered().sort, 'should have only filtered host'

        ENV['FILTER'] = 'host2 , host4'
        instance_setup
        assert_equal [@i2, @i4].sort, @instance.filtered().sort, 'should have only filtered hosts'

        ENV['FILTER'] = '-host2'
        instance_setup
        assert_equal [@i1, @i3, @i4].sort, @instance.filtered().sort, 'should not have negated hosts'

        ENV['FILTER'] = 'host1,host2,-host2'
        instance_setup
        assert_equal [@i1].sort, @instance.filtered().sort, 'should not have negated hosts'

        ENV['FILTER'] = 'host1~host3'
        instance_setup
        assert_equal [@i1, @i2, @i3].sort, @instance.filtered().sort, 'should allow range in filter'

        ENV['FILTER'] = '-host1~-host3'
        instance_setup
        assert_equal [@i4].sort, @instance.filtered().sort, 'should allow negative range in filter'

        ENV['FILTER'] = '-host1'
        ENV['FILTER_ROLES'] = 'role1'
        instance_setup
        assert_equal [@i2].sort, @instance.filtered().sort, 'should not have negated roles'
      end

      should "filter roles" do
        ENV['FILTER'] = nil
        ENV['FILTER_ROLES'] = 'role1'
        instance_setup
        assert_equal [@i1, @i2].sort, @instance.filtered().sort, 'should have only filtered roles'

        ENV['FILTER_ROLES'] = 'role1 , role2'
        instance_setup
        assert_equal [@i1, @i2, @i3, @i4].sort, @instance.filtered().sort, 'should have only filtered roles'

        ENV['FILTER_ROLES'] = '-role1'
        instance_setup
        assert_equal [@i3, @i4].sort, @instance.filtered().sort, 'should not have negated roles'

        ENV['FILTER_ROLES'] = 'role1~role2'
        instance_setup
        assert_equal [@i1, @i2, @i3, @i4].sort, @instance.filtered().sort, 'should allow range in filter'

        ENV['FILTER_ROLES'] = '-role1~-role2'
        instance_setup
        assert_equal [].sort, @instance.filtered().sort, 'should allow negative range in filter'
      end

      should "validate filters" do
        ENV['FILTER'] = "nohost"
        instance_setup
        assert_raises do
          @instance.filtered()
        end

        ENV['FILTER'] = "-nohost"
        instance_setup
        assert_raises do
          @instance.filtered()
        end

        ENV['FILTER_ROLES'] = "norole"
        instance_setup
        assert_raises do
          @instance.filtered()
        end

        ENV['FILTER_ROLES'] = "-norole"
        instance_setup
        assert_raises do
          @instance.filtered()
        end
      end
    end

    context "cloud storage" do
      require 'rubber/cloud/aws'
      require 'rubber/cloud/aws/classic'

      setup do
        env = {'access_key' => "XXX", 'secret_access_key' => "YYY", 'region' => "us-east-1"}
        env = Rubber::Configuration::Environment::BoundEnv.new(env, nil, nil, nil)
        @cloud = Rubber::Cloud::Aws::Classic.new(env, nil)
        @cloud.storage_provider.put_bucket('bucket')
        Rubber.stubs(:cloud).returns(@cloud)
      end

      should "fail for invalid instance_storage protocol" do
        Cluster.new('file:baz')

        @cloud.storage('bucket').store('key', '')
        Cluster.new('storage:bucket/key')

        TableConfigurationStorage.any_instance.stubs(:load)
        Cluster.new('table:bar')

        assert_raises { Cluster.new('foo:bar') }
      end

      should "load and save from file when file given" do
        location = "file:#{Tempfile.new('instancestorage').path}"

        FileConfigurationStorage.any_instance.expects(:load)
        cluster = Cluster.new(location)

        assert cluster.configuration_storage.is_a?(FileConfigurationStorage)

        cluster.configuration_storage.expects(:save)
        cluster.save
      end

      should "create new instance in filesystem when instance file doesn't exist" do
        tempfile = Tempfile.new('instancestorage')
        tempfile.close
        tempfile.unlink

        location = "file:#{tempfile.path}"
        FileConfigurationStorage.any_instance.expects(:load)

        cluster = Cluster.new(location)

        assert cluster.configuration_storage.is_a?(FileConfigurationStorage)

        cluster.configuration_storage.expects(:save)
        cluster.save
      end

      should "load and save from storage when storage given" do
        @cloud.storage('bucket').store('key', '')
        location = 'storage:bucket/key'

        cluster = assert_nothing_raised { Cluster.new(location) }

        assert cluster.configuration_storage.is_a?(S3ConfigurationStorage)

        cluster.configuration_storage.expects(:save)
        cluster.save
      end

      should "create a new instance in cloud storage when the instance file doesn't exist" do
        @cloud.storage('storage').ensure_bucket
        S3ConfigurationStorage.any_instance.expects(:load_from_file).never

        cluster = assert_nothing_raised { Cluster.new('storage:bucket/key') }
        assert cluster.configuration_storage.is_a?(S3ConfigurationStorage)

        cluster.configuration_storage.expects(:save)
        cluster.save
      end

      should "load and save from table when table given" do
        TableConfigurationStorage.any_instance.expects(:load)
        cluster = Cluster.new('table:foobar')

        assert cluster.configuration_storage.is_a?(TableConfigurationStorage)

        cluster.configuration_storage.expects(:save)
        cluster.save
      end

      should "backup on save when desired" do
        location_file = Tempfile.new('instancestorage').path
        location = "file:#{location_file}"
        backup_file = Tempfile.new('instancestoragebackup').path
        backup = "file:#{backup_file}"


        instance = Cluster.new(location, :backup => backup)
        instance.add(@i1 = InstanceItem.new('host1', 'domain.com', [RoleItem.new('role1')], '', 'm1.small', 'ami-7000f019'))
        instance.save

        location_data = File.read(location_file)
        backup_data = File.read(backup_file)
        assert location_data.size > 0
        assert backup_data.size > 0
        assert_equal location_data, backup_data
      end

    end

  end

end
