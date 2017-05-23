require File.expand_path(File.join(__FILE__, '../..', 'test_helper'))
require 'rubber/cloud/aws'
require 'ostruct'

class FogTest < Test::Unit::TestCase

  context "fog" do

    setup do
      env = { 'compute_credentials' =>
                 { 'aws_access_key_id' => 'XXX', 'aws_secret_access_key' => 'YYY', 'provider' => 'AWS'},
             'storage_credentials' =>
                 { 'aws_access_key_id' => 'XXX', 'aws_secret_access_key' => 'YYY', 'provider' => 'AWS'}}
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

    should "create instance with options" do
      assert @cloud.create_instance('', '', '', '', '', '', :foo => :bar)
    end
  end
end
