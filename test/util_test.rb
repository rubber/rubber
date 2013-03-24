require File.expand_path(File.join(__FILE__, '..', 'test_helper'))

class UtilTest < Test::Unit::TestCase
  include Rubber::Util

  should "safely convert arg to a string with stringify" do
    assert_equal "", stringify(nil)
    assert_equal "hi", stringify("hi")
    assert_equal "1", stringify(1)
    assert_equal "3.4", stringify(3.4)
    assert_equal ["1", "2", "r"], stringify([1, 2, "r"])
    assert_equal({"1" => "2", "three" => "four"}, stringify({1 => 2, :three => "four"}))
    assert_equal [{"3" => "4"}], stringify([{3 => 4}])
  end

  context "retry_on_failure" do

    class TestException1 < Exception; end
    class TestException2 < Exception; end
  
    should "have no impact on passing code" do
      expects(:puts).with("hello").once
      retry_on_failure(TestException1) do
        puts "hello"
      end
    end
  
    should "retry for specified exceptions" do
      expects(:puts).with("hello").at_least(2)
      assert_raise(TestException1) do
        retry_on_failure(TestException1) do
          puts "hello"
          raise TestException1.new
        end
      end
    end
  
    should "retry by given count for specified exceptions" do
      expects(:puts).with("hello").times(6)
      assert_raise(TestException1) do
        retry_on_failure(TestException1, TestException2, :retry_count => 5) do
          puts "hello"
          raise TestException1.new
        end
      end
    end
  
    should "not retry for unspecified exceptions" do
      expects(:puts).with("hello").once
      assert_raise(TestException1) do
        retry_on_failure(TestException2) do
          puts "hello"
          raise TestException1.new
        end
      end
    end
  
    should "sleep if retry_sleep given" do
      expects(:sleep).with(1).once
      assert_raise(TestException1) do
        retry_on_failure(TestException1, :retry_count => 1, :retry_sleep => 1) do
          raise TestException1.new
        end
      end
    end
  
    should "not sleep if retry_sleep not given" do
      expects(:sleep).never
      assert_raise(TestException1) do
        retry_on_failure(TestException1, :retry_count => 1) do
          raise TestException1.new
        end
      end
    end
  
  end
  
  context 'camelcase' do
    should 'handle single words' do
      assert_equal 'Aws', camelcase('aws')
    end

    should 'handle multiple words' do
      assert_equal 'DigitalOcean', camelcase('digital_ocean')
    end
  end
end
