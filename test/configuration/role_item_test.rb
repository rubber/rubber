require_relative '../test_helper'

require 'rubber/configuration/role_item'

class Rubber::Configuration::RoleItemTest < Test::Unit::TestCase
  include Rubber::Configuration

  should "be equal" do
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

  should "parse roles" do
    assert_equal RoleItem.new('a'), RoleItem.parse("a")
    assert_equal RoleItem.new('a', {'b' => 'c'}), RoleItem.parse("a:b=c")
    assert_equal RoleItem.new('a', {'b' => 'c', 'd' => 'e'}), RoleItem.parse("a:b=c;d=e")
    assert_equal RoleItem.new('a', {'b' => true, 'c' => false}), RoleItem.parse("a:b=true;c=false")
  end

  should "convert to a string" do
    assert_equal "a", RoleItem.new('a').to_s
    assert_equal "a:b=c", RoleItem.new('a', {'b' => 'c'}).to_s
    str = RoleItem.new('a', {'b' => 'c', 'd' => 'e'}).to_s
    assert ["a:b=c;d=e", "a:d=e;b=c"].include?(str)
    assert_equal "a:b=true", RoleItem.new('a', {'b' => true}).to_s
    assert_equal "a:b=false", RoleItem.new('a', {'b' => false}).to_s
  end

  context "role dependencies" do

    should "expand role dependencies" do
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

    should "expand dependencie for common role" do
      deps = { RoleItem.new('a') => RoleItem.new('b'),
               RoleItem.new('common') => [RoleItem.new('c')]}
      roles = [RoleItem.new('a'), RoleItem.new('b'), RoleItem.new('c')]
      assert_equal roles, RoleItem.expand_role_dependencies(RoleItem.new('a'), deps).sort
    end
  end
end
