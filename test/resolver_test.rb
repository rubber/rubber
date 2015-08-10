require File.expand_path(File.join(__FILE__, '..', 'test_helper'))

class ResolverTest < Test::Unit::TestCase

  def test_fails_lookup
    require 'resolv'

    assert_raises(Resolv::ResolvError) do
      Resolv.getaddress('test.example.com')
    end
  end

  def test_returns_public_ip_addresses_from_outside_cluster
    setup_cluster
    set_running_in_cluster(false)

    assert_equal '10.10.50.1', Resolv.getaddress('test.example.com')
    assert_equal 'test.example.com', Resolv.getname('10.10.50.1')
  end

  def test_returns_private_ip_addresses_from_inside_cluster
    setup_cluster
    set_running_in_cluster(true)

    assert_equal '192.168.50.1', Resolv.getaddress('test.example.com')
    assert_equal 'test.example.com', Resolv.getname('192.168.50.1')
  end

  private

  def setup_cluster
    ic = Rubber::Configuration::InstanceItem.new('test', 'example.com', [], 'instance_id', 'image_type', 'image_id')
    ic.external_ip = '10.10.50.1'
    ic.internal_ip = '192.168.50.1'

    Rubber.instances.add(ic)

    require_relative '../lib/rubber/resolver'
    ::Rubber::Resolver.instance.send(:clear_cache)
  end

  def set_running_in_cluster(running_in_cluster)
    Rubber::Resolver.instance.stubs(:running_in_cluster?).returns(running_in_cluster)
  end

end