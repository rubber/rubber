require 'test/unit'
require 'rubber/configuration'
require 'tempfile'

class EnvironmentTest < Test::Unit::TestCase
  include Rubber::Configuration

  def test_known_roles
    env = Rubber::Configuration::Environment.new("#{File.dirname(__FILE__)}/fixtures/rubber.yml")
    assert_equal ['role1', 'role2'], env.known_roles, "list of know roles not correct"
  end

  def test_env
    env = Rubber::Configuration::Environment.new("#{File.dirname(__FILE__)}/fixtures/testenv.yml")
    e = env.bind(nil, nil)
    assert_equal 'val1', e['var1'], 'env not retrieving right val'
    assert_equal 'val2', e['var2'], 'env not retrieving right val'
    assert_equal 'val1', e.var1, 'env not retrieving right val for method missing'
    assert_equal 'val2', e.var2, 'env not retrieving right val for method missing'

    e = env.bind('role1', 'nohost')
    assert_equal 'val1', e['var1'], 'env not retrieving right val'
    assert_equal 'role1val2', e['var2'], 'env not retrieving right val'
    assert_equal 'val1', e.var1, 'env not retrieving right val for method missing'
    assert_equal 'role1val2', e.var2, 'env not retrieving right val for method missing'

    e = env.bind('role1', 'host1')
    assert_equal 'val1', e['var1'], 'env not retrieving right val'
    assert_equal 'host1val2', e['var2'], 'env not retrieving right val'
    assert_equal 'val1', e.var1, 'env not retrieving right val for method missing'
    assert_equal 'host1val2', e.var2, 'env not retrieving right val for method missing'

    e = env.bind('norole', 'host1')
    assert_equal 'val1', e['var1'], 'env not retrieving right val'
    assert_equal 'host1val2', e['var2'], 'env not retrieving right val'
    assert_equal 'val1', e.var1, 'env not retrieving right val for method missing'
    assert_equal 'host1val2', e.var2, 'env not retrieving right val for method missing'
  end

  def test_combine
    env = Rubber::Configuration::Environment.new("nofile").bind("norole", "nohost")
    assert_equal "new", env.combine("old", "new"), "Last should win for scalar combine"
    assert_equal 5, env.combine(1, 5), "Last should win for scalar combine"
    assert_equal [1, 2, 3, 4], env.combine([1, 2, 3], [3, 4]), "Arrays should be unioned when combined"
    assert_equal({1 => "1", 2 => "2", 3 => "3", 4 => "4"}, env.combine({1 => "1", 2 => "2"}, {3 => "3", 4 => "4"}), "Maps should be unioned when combined")
    assert_equal({1 => "2"}, env.combine({1 => "1"}, {1 => "2"}), "Last should win for scalars in maps when combined")
    assert_equal({1 => {1 => "1", 2 => "2"}}, env.combine({1 => {1 => "1"}}, {1 => {2 => "2"}}), "Maps should be unioned recursively when combined")
  end

end
