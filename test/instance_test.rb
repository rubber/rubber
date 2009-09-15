require 'test/unit'
require 'tempfile'
require 'test_helper'

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

  def test_equality
    assert RoleItem.new('a').eql?(RoleItem.new('a'))
    assert RoleItem.new('a') == RoleItem.new('a')
    assert_equal RoleItem.new('a').hash, RoleItem.new('a').hash

    assert ! RoleItem.new('a').eql?(RoleItem.new('b'))
    assert RoleItem.new('a') != RoleItem.new('b')
    assert_not_equal RoleItem.new('a').hash, RoleItem.new('b').hash

    assert RoleItem.new('a', {'a' => 'b', 1 => true}).eql?(RoleItem.new('a', {'a' => 'b', 1 => true}))
    assert RoleItem.new('a', {'a' => 'b', 1 => true}) == RoleItem.new('a', {'a' => 'b', 1 => true})
    assert_equal RoleItem.new('a', {'a' => 'b', 1 => true}).hash, RoleItem.new('a', {'a' => 'b', 1 => true}).hash

    assert ! RoleItem.new('a', {'a' => 'b', 1 => true}).eql?(RoleItem.new('a', {'a' => 'b', 2 => true}))
    assert RoleItem.new('a', {'a' => 'b', 1 => true}) != RoleItem.new('a', {'a' => 'b', 2 => true})
    assert_equal RoleItem.new('a', {'a' => 'b', 1 => true}).hash, RoleItem.new('a', {'a' => 'b', 2 => true}).hash
  end

  def test_role_parse
    assert_equal RoleItem.new('a'), RoleItem.parse("a")
    assert_equal RoleItem.new('a', {'b' => 'c'}), RoleItem.parse("a:b=c")
    assert_equal RoleItem.new('a', {'b' => 'c', 'd' => 'e'}), RoleItem.parse("a:b=c;d=e")
    assert_equal RoleItem.new('a', {'b' => true, 'c' => false}), RoleItem.parse("a:b=true;c=false")
  end

  def test_role_to_s
    assert_equal "a", RoleItem.new('a').to_s
    assert_equal "a:b=c", RoleItem.new('a', {'b' => 'c'}).to_s
    assert_equal "a:b=c;d=e", RoleItem.new('a', {'b' => 'c', 'd' => 'e'}).to_s
    assert_equal "a:b=true;c=false", RoleItem.new('a', {'b' => true, 'c' => false}).to_s
  end

  def test_expand_role_dependencies
    deps = { RoleItem.new('a') => RoleItem.new('b'),
             RoleItem.new('b') => RoleItem.new('c'),
             RoleItem.new('c') => [RoleItem.new('d'), RoleItem.new('a')]}
    roles = [RoleItem.new('a'),RoleItem.new('b'),RoleItem.new('c'),RoleItem.new('d')]
    assert_equal roles, RoleItem.expand_role_dependencies(RoleItem.new('a'), deps).sort
    assert_equal roles, RoleItem.expand_role_dependencies([RoleItem.new('a'), RoleItem.new('d')], deps).sort

    deps = { RoleItem.new('mysql_master') => RoleItem.new('db', {'primary' => true}),
             RoleItem.new('mysql_slave') => RoleItem.new('db'),
             RoleItem.new('db', {'primary' => true}) => RoleItem.new('mysql_master'),
             RoleItem.new('db') => RoleItem.new('mysql_slave')
    }
    assert_equal [RoleItem.new('db', 'primary' => true), RoleItem.new('mysql_master')],
                 RoleItem.expand_role_dependencies(RoleItem.new('mysql_master'), deps).sort
    assert_equal [RoleItem.new('db', 'primary' => true), RoleItem.new('mysql_master')],
                 RoleItem.expand_role_dependencies(RoleItem.new('db', 'primary' => true), deps).sort
    assert_equal [RoleItem.new('db'), RoleItem.new('mysql_slave')],
                 RoleItem.expand_role_dependencies(RoleItem.new('mysql_slave'), deps).sort
    assert_equal [RoleItem.new('db'), RoleItem.new('mysql_slave')],
                 RoleItem.expand_role_dependencies(RoleItem.new('db'), deps).sort

  end
end
