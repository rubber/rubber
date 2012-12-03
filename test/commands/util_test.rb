require File.expand_path(File.join(__FILE__, '../..', 'test_helper'))

class UtilTest < Test::Unit::TestCase

  def setup
    @project_root = File.expand_path(File.join(__FILE__, '../../..'))
    @rubber = "#{@project_root}/bin/rubber"
    @key = Rubber::Encryption.generate_encrypt_key
    ENV['RUBBER_ROOT'] = @project_root
  end
  
  context "obfuscate_rubber_secret" do

    should "generate a key" do
      out = `#{@rubber} util:obfuscate_rubber_secret -g`
      assert_equal 0, $?, "Process failed, output: #{out}"
      assert_match /Obfuscation key: [^\n\s]+/, out
    end
    
    should "encrypt and decrypt rubber-secret.yml" do
      fixture_dir = File.expand_path("#{File.dirname(__FILE__)}/../fixtures/secret")
      out = `#{@rubber} util:obfuscate_rubber_secret -f '#{fixture_dir}/secret.yml' -k '#{@key}'`
      assert_equal 0, $?, "Process failed, output: #{out}"
      assert out.size > 0
      assert_no_match /secret_key: secret_val/, out
      
      tempfile = Tempfile.new('encryptedsecret')
      open(tempfile.path, "w") {|f| f.write(out) }
      
      out2 = `#{@rubber} util:obfuscate_rubber_secret -f '#{tempfile.path}' -k '#{@key}' -d`
      assert_equal 0, $?, "Process failed, output: #{out2}"
      assert out2.size > 0
      assert_match /secret_key: secret_val/, out2
    end

  end
  
end
