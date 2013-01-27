require File.expand_path(File.join(__FILE__, '..', 'test_helper'))
require 'rubber/encryption'

class EncryptionTest < Test::Unit::TestCase
  include Rubber::Encryption
  
  should "generate a unique encryption key" do
    k1, k2 = generate_encrypt_key, generate_encrypt_key
    assert k1
    assert k2
    assert k1 != k2
  end
  
  context "encryption" do
  
    setup do
      @key = generate_encrypt_key
    end
  
    should "encrypt data" do
      pend('This is not yet working on JRuby.') if defined?(JRUBY_VERSION)

      data = "hello"
      e = encrypt(data, @key)
      assert e
      assert e.size > 0
      assert e != data
    end

    should "decrypt data" do
      pend('This is not yet working on JRuby.') if defined?(JRUBY_VERSION)

      data = "hello"
      e = encrypt(data, @key)
      d = decrypt(e, @key)
      assert data == d
    end
    
    should "pretty print large data" do
      pend('This is not yet working on JRuby.') if defined?(JRUBY_VERSION)

      data = "foo" * 100
      e = encrypt(data, @key)
      assert e =~ /\n/
    end
    
    should "roundtrip large data" do
      pend('This is not yet working on JRuby.') if defined?(JRUBY_VERSION)

      data = "foo" * 100
      e = encrypt(data, @key)
      d = decrypt(e, @key)
      assert data == d
    end
    
  end
  
end

