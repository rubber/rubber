require File.expand_path(File.join(__FILE__, '../..', 'test_helper'))
require 'rubber/cloud/aws'
require 'ostruct'

class AwsTest < Test::Unit::TestCase

  context "aws" do

    setup do
      env = {'access_key' => "XXX", 'secret_access_key' => "YYY", 'region' => "us-east-1"}
      env = Rubber::Configuration::Environment::BoundEnv.new(env, nil, nil, nil)
      @cloud = Rubber::Cloud::Aws.new(env, nil)
    end

    should "instantiate" do
      assert @cloud.compute_provider
      assert @cloud.storage_provider
    end

    should "provide storage" do
      assert @cloud.storage('mybucket')
    end

    should "provide table store" do
      assert @cloud.table_store('somekey')
    end

    should "create instance" do
      assert @cloud.create_instance('', '', '', '', '', '')
    end
  end

  context "aws with alternative region" do
    
    setup do
      @region = "ap-southeast-2"
      env = {'access_key' => "XXX", 'secret_access_key' => "YYY", 'region' => @region}
      env = Rubber::Configuration::Environment::BoundEnv.new(env, nil, nil, nil)
      @cloud = Rubber::Cloud::Aws.new(env, nil)
    end

    should "set region on compute provider" do
      assert_equal @cloud.compute_provider.region, @region
    end

    should "set region on storage provider" do
      assert_equal @cloud.storage_provider.region, @region
    end
  end
end
