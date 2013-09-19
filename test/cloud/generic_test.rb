require File.expand_path(File.join(__FILE__, '../..', 'test_helper'))
require 'rubber/cloud/generic'
require 'ostruct'

class GenericTest < Test::Unit::TestCase

  context "generic with aws storage with alternative region" do
    
    setup do
      @aws_region = "ap-southeast-2"
      env = {'cloud_providers' => {'aws' => {'access_key' => "XXX", 'secret_access_key' => "YYY", 'region' => @aws_region}}}
      env = Rubber::Configuration::Environment::BoundEnv.new(env, nil, nil, nil)
      @cloud = Rubber::Cloud::Generic.new(env, nil)
    end

    should "set region on storage provider" do
      assert_equal @cloud.storage_provider.region, @aws_region
    end
  end
end
