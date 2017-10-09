require_relative '../test_helper'

require 'rubber/configuration/instance_item'

class Rubber::Configuration::InstanceItemTest < Test::Unit::TestCase
  include Rubber::Configuration

  setup do
    @hash = {
      'name' => 'host1',
      'domain' => 'domain.com',
      'roles' => ['role1', 'db:primary=true'],
      'instance_id' => 'xxxyyy',
      'image_type' => 'm1.small',
      'image_id' => 'ami-7000f019',
      'security_groups' => ['sg1', 'sg2']
    }
  end

  should "create from a hash" do
    item = InstanceItem.from_hash(@hash)
    assert_equal 'host1', item.name
    assert_equal 'domain.com', item.domain
    assert_equal [RoleItem.new('role1'), RoleItem.new('db', {'primary' => true})], item.roles
    assert_equal 'xxxyyy', item.instance_id
    assert_equal 'm1.small', item.image_type
    assert_equal 'ami-7000f019', item.image_id
    assert_equal ['sg1', 'sg2'], item.security_groups
  end

  should "output as a hash" do
    item = InstanceItem.new('host1',
                            'domain.com',
                            [RoleItem.new('role1'), RoleItem.new('db', {'primary' => true})],
                            'xxxyyy',
                            'm1.small',
                            'ami-7000f019',
                            ['sg1', 'sg2'])
    assert_equal @hash, item.to_hash()
  end
end
