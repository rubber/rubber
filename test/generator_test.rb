require File.expand_path(File.join(__FILE__, '..', 'test_helper'))

class GeneratorTest < Test::Unit::TestCase
  include Rubber::Configuration

  def test_validate
    assert_raise RuntimeError do
      src = <<-SRC
        hello
      SRC
      Generator.new(nil, nil, nil).transform(src)
    end
    assert_raise RuntimeError do
      src = <<-SRC
        <%
          @read_cmd = 'ls'
        %>
        hello
      SRC
      Generator.new(nil, nil, nil).transform(src)
    end
    assert_raise RuntimeError do
      src = <<-SRC
        <%
          @write_cmd = 'cat'
        %>
        hello
      SRC
      Generator.new(nil, nil, nil).transform(src)
    end
  end

  def test_simple_transform
    out_file = Tempfile.new('testsimple')
    src = <<-SRC
      <%
        @path = '#{out_file.path}'
      %>
      hello
    SRC

    Generator.new(nil, nil, nil).transform(src)
    assert File.exists?(out_file.path), "transform did not generate an output file"
    assert_equal "hello", File.read(out_file.path).strip, "transformed contents are incorrect"
  end

  def test_additive_transform
    out_file = Tempfile.new('testadditive')
    open(out_file.path, 'w') { |f| f.write("howdy\n")}
    src = <<-SRC
      <%
        @path = '#{out_file.path}'
        @additive = ['#start', '#end']
      %>
      hello
    SRC

    Generator.new(nil, nil, nil).transform(src)
    assert File.exists?(out_file.path), "transform did not generate an output file"
    assert_equal "howdy\n#start      \n      hello\n#end", File.read(out_file.path).strip, "transformed contents are incorrect"

    src += "neato\n"
    open(out_file.path, 'a') { |f| f.write("again\n")}
    Generator.new(nil, nil, nil).transform(src)
    assert File.exists?(out_file.path), "transform did not generate an output file"
    assert_equal "howdy\n#start      \n      hello\nneato\n#end\nagain", File.read(out_file.path).strip, "transformed contents are incorrect"
  end

  def test_post_command
    out_file = Tempfile.new('testpost')
    post_file = out_file.path + '.post'
    src = <<-SRC
      <%
        @path = '#{out_file.path}'
        @post = 'touch #{post_file}'
      %>
      hello
    SRC

    Generator.new(nil, nil, nil).transform(src)
    assert File.exists?(out_file.path), "transform did not generate an output file"
    assert File.exists?(post_file), "transform did not execute post"
    assert_equal "hello", File.read(out_file.path).strip, "transformed contents are incorrect"

    FileUtils.rm_f(post_file)
    Generator.new(nil, nil, nil).transform(src)
    assert File.exists?(out_file.path), "transform did not generate an output file"
    assert ! File.exists?(post_file), "post should not have been executed as dest file unchanged"
    assert_equal "hello", File.read(out_file.path).strip, "transformed contents are incorrect"

    FileUtils.rm_f(post_file)
    gen = Generator.new(nil, nil, nil)
    gen.force = true
    gen.transform(src)
    assert File.exists?(out_file.path), "transform did not generate an output file"
    assert File.exists?(post_file), "forced transform did not execute post"
    assert_equal "hello", File.read(out_file.path).strip, "transformed contents are incorrect"

    FileUtils.rm_f(post_file)
    gen = Generator.new(nil, nil, nil)
    gen.no_post = true
    gen.transform(src + "there")
    assert File.exists?(out_file.path), "transform did not generate an output file"
    assert ! File.exists?(post_file), "post should not have been generated for no_post option"
    assert_equal "hello\nthere", File.read(out_file.path).strip, "transformed contents are incorrect"
  end

  def test_delayed_post_command
    out_dir = "#{Dir::tmpdir}/test_rubber_delayed_post"
    FileUtils.rm_rf(out_dir)
    assert ! File.exists?(out_dir)

    g = Generator.new("#{File.dirname(__FILE__)}/fixtures/basic", nil, nil, :out_dir => out_dir)

    post_file = "#{out_dir}/post"

    src1 = <<-SRC
      <%
        @path = "#{out_dir}/src1"
        @delayed_post = 'echo `date` >> #{post_file}'
      %>
      contents1
    SRC

    src2 = <<-SRC
      <%
        @path = "#{out_dir}/src2"
        @delayed_post = 'echo `date` >> #{post_file}'
      %>
      contents2
    SRC

    src3 = <<-SRC
      <%
        @path = "#{out_dir}/src3"
        @delayed_post = 'echo 3 `date` >> #{post_file}'
      %>
      contents3
    SRC

    g.transform(src1)
    g.transform(src2)
    g.transform(src3)

    assert File.exists?("#{out_dir}/src1"), "transform did not generate an output file"
    assert ! File.exists?(post_file), "transform executed delayed post early"
    assert_equal "contents1", File.read("#{out_dir}/src1").strip, "transformed contents are incorrect"

    assert File.exists?("#{out_dir}/src2"), "transform did not generate an output file"
    assert ! File.exists?(post_file), "transform executed delayed post early"
    assert_equal "contents2", File.read("#{out_dir}/src2").strip, "transformed contents are incorrect"

    assert File.exists?("#{out_dir}/src3"), "transform did not generate an output file"
    assert ! File.exists?(post_file), "transform executed delayed post early"
    assert_equal "contents3", File.read("#{out_dir}/src3").strip, "transformed contents are incorrect"

    g.run()
    assert File.exists?(post_file), "delayed post was not executed"
    assert_equal 2, File.read(post_file).lines.to_a.size, "delayed post was not de-duped"
  end

  def test_stop_on_error
    out_file = Tempfile.new('teststoponerr')
    post_file = out_file.path + '.post'
    src = <<-SRC
      <%
        @path = '#{out_file.path}'
        @post = 'badcommand; touch #{post_file}'
      %>
      hello
    SRC

    g = Generator.new(nil, nil, nil)
    g.transform(src)
    assert File.exists?(out_file.path), "transform did not generate an output file"
    assert File.exists?(post_file), "transform did not execute post"
    assert_equal "hello", File.read(out_file.path).strip, "transformed contents are incorrect"

    FileUtils.rm_f(post_file)
    g = Generator.new(nil, nil, nil)
    g.stop_on_error_cmd = "function error_exit { exit 99; }; trap error_exit ERR"
    g.transform(src)
    assert File.exists?(out_file.path), "transform did not generate an output file"
    assert ! File.exists?(post_file), "post should not have been executed as comes after error"
  end

  def test_pipe_command
    out_file = Tempfile.new('testpipe')
    src = <<-SRC
      <%
        @read_cmd = 'echo hi'
        @write_cmd = 'cat > #{out_file.path}'
      %>
      hello
    SRC

    Generator.new(nil, nil, nil).transform(src)
    assert File.exists?(out_file.path), "transform did not generate to write_cmd"
    assert_equal "hello", File.read(out_file.path).strip, "transformed contents are incorrect"

    FileUtils.rm_f(out_file.path)
    src = <<-SRC
      <%
        @read_cmd = 'echo hi'
        @write_cmd = 'cat > #{out_file.path}'
        @additive = ['#start', '#end']
      %>
      hello
    SRC

    Generator.new(nil, nil, nil).transform(src)
    assert File.exists?(out_file.path), "transform did not generate to write_cmd"
    assert_equal "hi\n#start      \n      hello\n#end", File.read(out_file.path).strip, "transformed contents are incorrect"

    FileUtils.rm_f(out_file.path)
    src = <<-SRC
      <%
        @read_cmd = 'echo "#start\nthere\n#end\nhi\n"'
        @write_cmd = 'cat > #{out_file.path}'
        @additive = ['#start', '#end']
      %>
      hello
    SRC

    Generator.new(nil, nil, nil).transform(src)
    assert File.exists?(out_file.path), "transform did not generate to write_cmd"
    assert_equal "#start      \n      hello\n#end\nhi", File.read(out_file.path).strip, "transformed contents are incorrect"
    
    FileUtils.rm_f(out_file.path)
    src = <<-SRC
      <%
        @read_cmd = 'echo hi'
        @write_cmd = 'badcommand'
      %>
      hello
    SRC

    assert_raises do
      Generator.new(nil, nil, nil).transform(src)
    end
    
  end

  def list_dir(dir)
    l = Dir.entries(dir).sort
    l.delete_if {|d| d =~ /(^\.+$)|\.bak$/}
  end

  def test_scoping
    out_dir = "#{Dir::tmpdir}/test_rubber_scoping"
    FileUtils.rm_rf(out_dir)
    assert ! File.exists?(out_dir)

    g = Generator.new("#{File.dirname(__FILE__)}/fixtures/basic", nil, nil, :out_dir => out_dir)
    g.run()
    assert File.directory?(out_dir), "scoped transform did not create dir"
    assert_equal ['bar.conf', 'foo.conf'], list_dir(out_dir), "scoped transform did not create correct files"
    assert_equal "common", File.read("#{out_dir}/foo.conf").strip, "transformed contents are incorrect"
    assert_equal "common", File.read("#{out_dir}/bar.conf").strip, "transformed contents are incorrect"

    FileUtils.rm_rf(out_dir)
    assert ! File.exists?(out_dir)

    g = Generator.new("#{File.dirname(__FILE__)}/fixtures/basic", ['role1'], nil, :out_dir => out_dir)
    g.run()
    assert File.directory?(out_dir), "scoped transform did not create dir"
    assert_equal ['bar.conf', 'foo.conf'], list_dir(out_dir), "scoped transform did not create correct files"
    assert_equal "role1", File.read("#{out_dir}/foo.conf").strip, "transformed contents are incorrect"
    assert_equal "common", File.read("#{out_dir}/bar.conf").strip, "transformed contents are incorrect"

    FileUtils.rm_rf(out_dir)
    assert ! File.exists?(out_dir)

    g = Generator.new("#{File.dirname(__FILE__)}/fixtures/basic", ['role2', 'role1'], nil, :out_dir => out_dir)
    g.run()
    assert File.directory?(out_dir), "scoped transform did not create dir"
    assert_equal ['bar.conf', 'foo.conf'], list_dir(out_dir), "scoped transform did not create correct files"
    assert_equal "role2", File.read("#{out_dir}/foo.conf").strip, "transformed contents are incorrect"
    assert_equal "common", File.read("#{out_dir}/bar.conf").strip, "transformed contents are incorrect"

    FileUtils.rm_rf(out_dir)
    assert ! File.exists?(out_dir)

    g = Generator.new("#{File.dirname(__FILE__)}/fixtures/basic", ['role1'], 'host1', :out_dir => out_dir)
    g.run()
    assert File.directory?(out_dir), "scoped transform did not create dir"
    assert_equal ['bar.conf', 'foo.conf'], list_dir(out_dir), "scoped transform did not create correct files"
    assert_equal "host1", File.read("#{out_dir}/foo.conf").strip, "transformed contents are incorrect"
    assert_equal "common", File.read("#{out_dir}/bar.conf").strip, "transformed contents are incorrect"


    FileUtils.rm_rf(out_dir)
  end

  def test_ordering_of_additive
    out_dir = "#{Dir::tmpdir}/test_rubber_ordering"
    FileUtils.rm_rf(out_dir)
    assert ! File.exists?(out_dir)
    
    g = Generator.new("#{File.dirname(__FILE__)}/fixtures/generator_order", ['role2', 'role1'], 'host1', :out_dir => out_dir)
    g.run()
    assert File.directory?(out_dir), "transform did not create dir"
    assert_equal ['out.conf'], list_dir(out_dir), "transform did not create correct file"
    result = <<DATA
# common first start
first
# common first end
# common last start
last
# common last end
# role1 first start
role1 first
# role1 first end
# role1 last start
role1 last
# role1 last end
# role2 first start
role2 first
# role2 first end
# role2 last start
role2 last
# role2 last end
# host1 first start
host1 first
# host1 first end
# host1 last start
host1 last
# host1 last end
DATA
    assert_equal result.strip, File.read("#{out_dir}/out.conf").strip, "transformed contents are incorrect"
    
    FileUtils.rm_rf(out_dir)
  end

def test_file_pattern
    out_dir = "#{Dir::tmpdir}/test_rubber_scoping"
    FileUtils.rm_rf(out_dir)
    assert ! File.exists?(out_dir)

    g = Generator.new("#{File.dirname(__FILE__)}/fixtures/basic", nil, nil, :out_dir => out_dir)
    g.file_pattern = 'foo\.conf'
    g.run()
    assert File.directory?(out_dir), "scoped transform did not create dir"
    assert_equal ['foo.conf'], list_dir(out_dir), "scoped transform did not create correct files"
    assert_equal "common", File.read("#{out_dir}/foo.conf").strip, "transformed contents are incorrect"
  end

  def test_perms
    user = ENV['USER']
    group = `groups`.split.last
    out_file = Tempfile.new('testperms')
    src = <<-SRC
      <%
        @path = '#{out_file.path}'
        @perms = 0777
        @owner = '#{user}'
        @group = '#{group}'
      %>
      hello
    SRC

    Generator.new(nil, nil, nil).transform(src)
    assert File.exists?(out_file.path), "transform did not generate an output file"
    assert_equal "100777", sprintf("%o", File.stat(out_file.path).mode), "transformed permissions are incorrect"
    assert_equal Etc.getpwnam(user).uid, File.stat(out_file.path).uid, "transformed owner is incorrect"
    assert_equal Etc.getgrnam(group).gid,  File.stat(out_file.path).gid, "transformed group is incorrect"
  end

  def test_skip
    out_file = Tempfile.new('testskip')
    File.delete(out_file.path)
    src = <<-SRC
      <%
        @skip = true
        @path = '#{out_file.path}'
      %>
      hello
    SRC

    Generator.new(nil, nil, nil).transform(src)
    assert ! File.exists?(out_file.path), "transform didn't skip generation of an output file"
  end

  def test_backup
    out_file = Tempfile.new('testbak')
    assert ! File.exists?("#{out_file.path}.bak")
    File.open(out_file.path, 'w') {|f| f.write("howdy")}
    
    src = <<-SRC
      <%
        @path = '#{out_file.path}'
      %>
     hello <%= Time.now.to_f %>
    SRC

    Generator.new(nil, nil, nil).transform(src)

    assert File.exists?("#{out_file.path}.bak"), "transform didn't generate backup"
    assert_match /howdy/, File.read("#{out_file.path}.bak"), "transform backup has wrong contents"
  end

  def test_no_backup
    out_file = Tempfile.new('testnobak')
    assert ! File.exists?("#{out_file.path}.bak")
    File.open(out_file.path, 'w') {|f| f.write("howdy")}
    src = <<-SRC
      <%
        @path = '#{out_file.path}'
        @backup = false
      %>
     hello <%= Time.now.to_f %>
    SRC

    Generator.new(nil, nil, nil).transform(src)

    assert ! File.exists?("#{out_file.path}.bak"), "transform shouldn't generate backup"
  end

end
