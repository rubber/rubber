require 'test/unit'
require 'rubber/configuration'
require 'tempfile'

class InstanceTest < Test::Unit::TestCase
  include Rubber::Configuration

  def setup
    @instance = Instance.new(Tempfile.new('testforrole').path)
    @instance.add(@i1 = InstanceItem.new('host1', 'domain.com', [RoleItem.new('role1')], ''))
    @instance.add(@i2 = InstanceItem.new('host2', 'domain.com', [RoleItem.new('role1')], ''))
    @instance.add(@i3 = InstanceItem.new('host3', 'domain.com', [RoleItem.new('role2')], ''))
    @instance.add(@i4 = InstanceItem.new('host4', 'domain.com', [RoleItem.new('role2', 'primary' => true)], ''))
  end

  def test_for_role
    assert_equal 2, @instance.for_role('role1').size, 'not finding correct instances for role'
    assert_equal 2, @instance.for_role('role2').size, 'not finding correct instances for role'
    assert_equal 1, @instance.for_role('role2', {}).size, 'not finding correct instances for role'
    assert_equal @i3, @instance.for_role('role2', {}).first, 'not finding correct instances for role'
    assert_equal 1, @instance.for_role('role2', 'primary' => true).size, 'not finding correct instances for role'
    assert_equal @i4, @instance.for_role('role2', 'primary' => true).first, 'not finding correct instances for role'
  end

  def test_filtered
    assert_equal 4, @instance.filtered().size, 'should not filter for empty FILTER'
    
    ENV['FILTER'] = 'host1'
    setup
    assert_equal [@i1], @instance.filtered(), 'should have only filtered host'
    
    ENV['FILTER'] = 'host2 , host4'
    setup
    assert_equal [@i2, @i4], @instance.filtered(), 'should have only filtered hosts'
    
  end

end
