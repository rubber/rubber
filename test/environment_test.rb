require File.expand_path(File.join(__FILE__, '..', 'test_helper'))

class EnvironmentTest < Test::Unit::TestCase
  include Rubber::Configuration

  def test_known_roles
    env = Rubber::Configuration::Environment.new("#{File.dirname(__FILE__)}/fixtures/basic", 'test')
    assert_equal ['role1', 'role2', 'role3', 'role4', 'role5'], env.known_roles, "list of known roles not correct"
  end

  def test_env
    env = Rubber::Configuration::Environment.new("#{File.dirname(__FILE__)}/fixtures/basic", 'test')
    e = env.bind()
    assert_equal 'val1', e['var1'], 'env not retrieving right val'
    assert_equal 'val2', e['var2'], 'env not retrieving right val'
    assert_equal 'val1', e.var1, 'env not retrieving right val for method missing'
    assert_equal 'val2', e.var2, 'env not retrieving right val for method missing'
    
    assert_equal 'val3', e.var3, 'env not retrieving right val for config in supplemental file'

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

  def test_env_override
    env = Rubber::Configuration::Environment.new("#{File.dirname(__FILE__)}/fixtures/basic", 'test')
    e = env.bind()
    assert_equal 'val1', e['var1'], 'should be global val with no overrides'
    assert_equal 'val2', e['var2'], 'should be global val with no overrides'
    
    env = Rubber::Configuration::Environment.new("#{File.dirname(__FILE__)}/fixtures/basic", 'env1')
    e = env.bind(nil, nil)
    assert_equal 'env1val1', e['var1'], 'should be val from env override'
    assert_equal 'env1val2', e['var2'], 'should be val from env override'
    
    env = Rubber::Configuration::Environment.new("#{File.dirname(__FILE__)}/fixtures/basic", 'env1')
    e = env.bind('role1', nil)
    assert_equal 'env1val2', e['var2'], 'env override should win against role'
    
    env = Rubber::Configuration::Environment.new("#{File.dirname(__FILE__)}/fixtures/basic", 'env1')
    e = env.bind(nil, 'host1')
    assert_equal 'host1val2', e['var2'], 'host override should win against env'    
  end
  
  def test_host_override
    env = Rubber::Configuration::Environment.new("#{File.dirname(__FILE__)}/fixtures/basic", 'test')
    e = env.bind('norole', 'host2')
    assert_equal 'host2val3', e['var3'], 'env not retrieving right val'
    assert_equal %w[host2val4a host2val4b], e['var4'], 'env not retrieving right val'
    assert_equal [{'var51a' => 'val51a', 'var52a' => 'val52a'}, {'var53' => 'val53'}, {'var54' => 'val54'}], e['var5'], 'env not retrieving right val'
  end

  def test_combine
    env = Rubber::Configuration::Environment
    assert_equal "new", env.combine("old", "new"), "Last should win for scalar combine"
    assert_equal 5, env.combine(1, 5), "Last should win for scalar combine"
    assert_equal [1, 2, 3, 4], env.combine([1, 2, 3], [3, 4]), "Arrays should be unioned when combined"
    assert_equal({1 => "1", 2 => "2", 3 => "3", 4 => "4"}, env.combine({1 => "1", 2 => "2"}, {3 => "3", 4 => "4"}), "Maps should be unioned when combined")
    assert_equal({1 => "2"}, env.combine({1 => "1"}, {1 => "2"}), "Last should win for scalars in maps when combined")
    assert_equal({1 => {1 => "1", 2 => "2"}}, env.combine({1 => {1 => "1"}}, {1 => {2 => "2"}}), "Maps should be unioned recursively when combined")
  end

  def test_combine_override
    env = Rubber::Configuration::Environment
    assert_equal({"x" => 4, "y" => 2, "z" => 3}, env.combine({"x" => 1, "y" => 2}, {"^x" => 4, "z" => 3}), "scalars should override")
    assert_equal({"x" => [3, 4]}, env.combine({"x" => [1, 2]}, {"^x" => [3, 4]}), "lists should override")
    assert_equal({"x" => {"y" => [3, 4]}}, env.combine({"x" => {"y" => [1, 2]}}, {"x" => {"^y" => [3, 4]}}), "Maps should override recursively")
  end

  def test_expansion
    env = Rubber::Configuration::Environment.new("#{File.dirname(__FILE__)}/fixtures/expansion", 'test')
    e = env.bind()
    assert_equal 'val1', e['var1']
    assert_equal 'val2', e['var2']
    assert_equal 'val1', e['var3']
    assert_equal '4 is val2', e['var4']
    assert_equal 'val1', e['var5']
    assert_equal %w[lv1 lv2 val1], e['list1']
    expected = {'mk1' => 'mv1', 'mk2' => 'mv2', 'mk3' => 'val2'}
    e.map1.each do |k, v|
      assert_equal expected[k], v
    end
    Array(e.map1).each do |k, v|
      assert_equal expected[k], v
    end
      
    e = env.bind('role1', 'nohost')
    assert_equal 'role1val1', e['var1']
    assert_equal 'role1val1', e['var3']
    assert_equal %w[lv1 lv2 role1val1 role1lv1 role1val2], e['list1']

    e = env.bind('role1', 'host1')
    assert_equal 'host1val1', e['var1']
    assert_equal 'host1val1', e['var3']
    assert_equal %w[lv1 lv2 host1val1 role1lv1 host1val2 host1lv1], e['list1'] # lists are additive
    
    e = env.bind('norole', 'host1')
    assert_equal 'host1val1', e['var1']
    assert_equal 'host1val1', e['var3']
    assert_equal %w[lv1 lv2 host1val1 host1lv1 host1val2], e['list1']
  end

  def test_bool_expansion
    env = Rubber::Configuration::Environment.new("#{File.dirname(__FILE__)}/fixtures/expansion", 'test')
    e = env.bind()
    assert_equal true, e['truevar']
    assert_equal false, e['falsevar']
    assert_equal true, e['truevar_exp']
    assert 'true' != e['truevar_exp']
    assert_equal false, e['falsevar_exp']
    assert 'false' != e['falsevar_exp']
    assert_equal 'true thing', e['faketruevar_exp']      
  end

  def test_secret_env
    env = Rubber::Configuration::Environment.new("#{File.dirname(__FILE__)}/fixtures/basic", 'test')
    e = env.bind()
    assert_nil e['rubber_secret'], 'env should not have secret set'
    
    fixture_dir = File.expand_path("#{File.dirname(__FILE__)}/fixtures/secret")
    env = Rubber::Configuration::Environment.new(fixture_dir, 'test')
    e = env.bind()
    assert_equal "#{fixture_dir}/secret.yml", e['rubber_secret'], 'env should have secret set'
    assert_equal "secret_val", e['secret_key'], 'env should have gotten setting from secret file'    
  end

  def test_obfuscated_secret_env
    env = Rubber::Configuration::Environment.new("#{File.dirname(__FILE__)}/fixtures/basic", 'test')
    e = env.bind()
    assert_nil e['rubber_secret'], 'env should not have secret set'
    
    fixture_dir = File.expand_path("#{File.dirname(__FILE__)}/fixtures/obfuscated")
    env = Rubber::Configuration::Environment.new(fixture_dir, 'test')
    e = env.bind()
    assert_equal "#{fixture_dir}/secret.yml", e['rubber_secret'], 'env should have secret set'
    assert_equal "secret_val", e['secret_key'], 'env should have gotten setting from secret file'    
  end

  def test_nested_ref
    env = Rubber::Configuration::Environment.new("#{File.dirname(__FILE__)}/fixtures/nested", 'test')
    e = env.bind()
    assert_equal 'val1', e.var1, 'env not retrieving right val'
    assert_equal 'val3', e.var2.var3, 'env not retrieving right val'
    assert_equal({'var5' => 'val5'}, e.var2.var4, 'env not retrieving right val')
    assert_equal ['val6a', 'val6b'], e.var2.var6, 'env not retrieving right val'
    assert_equal 'val1', e.var2.var7, 'env not retrieving right val'
    assert_equal 'val3', e.var2.var8, 'env not retrieving right val'
    assert_equal 'val5', e.var2.var9, 'env not retrieving right val'
  end

  def test_instances_in_expansion
    config = Rubber::Configuration::get_configuration('test', "#{File.dirname(__FILE__)}/fixtures/instance_expansion")
    config.environment
    e = config.environment.bind()
    e.stubs(:rubber_instances).returns(config.instance)
    assert_equal "50.1.1.1", e['var1']
  end

  def test_erb_yml
    env = Rubber::Configuration::Environment.new("#{File.dirname(__FILE__)}/fixtures/basic", 'test')
    e = env.bind()
    assert_equal [0, 1, 2], e["erb_var"], 'should be able to generate env using erb'    
  end
  
end
