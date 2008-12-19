require 'test/unit'
require 'rubber/util'

class UtilTest < Test::Unit::TestCase

  def test_stringify
    assert_equal "", Rubber::Util::stringify(nil)
    assert_equal "hi", Rubber::Util::stringify("hi")
    assert_equal "1", Rubber::Util::stringify(1)
    assert_equal "3.4", Rubber::Util::stringify(3.4)
    assert_equal ["1", "2", "r"], Rubber::Util::stringify([1, 2, "r"])
    assert_equal({"1" => "2", "three" => "four"}, Rubber::Util::stringify({1 => 2, :three => "four"}))
    assert_equal [{"3" => "4"}], Rubber::Util::stringify([{3 => 4}])
  end

end
