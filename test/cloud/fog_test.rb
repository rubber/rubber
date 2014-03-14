require File.expand_path(File.join(__FILE__, '../..', 'test_helper'))
require 'rubber/cloud/aws'
require 'ostruct'

class FogTest < Test::Unit::TestCase

  context "fog" do

    setup do
      env = { 'compute_credentials' =>
                 { 'rackspace_api_key' => 'XXX', 'rackspace_username' => 'YYY', 'provider' => 'rackspace'},
             'storage_credentials' =>
                 { 'rackspace_api_key' => 'XXX', 'rackspace_username' => 'YYY', 'provider' => 'rackspace'}}
      env = Rubber::Configuration::Environment::BoundEnv.new(env, nil, nil, nil)
      @cloud = Rubber::Cloud::Fog.new(env, nil)
    end

    should "instantiate" do
      assert @cloud.compute_provider
      assert @cloud.storage_provider
    end

    should "provide storage" do
      assert @cloud.storage('mybucket')
    end

    should "not provide table store" do
      assert_raises { @cloud.table_store('somekey') }
    end

    should "create instance" do
      assert @cloud.create_instance('', '', '', '', '', '')
    end

  end
end
