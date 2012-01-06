require File.expand_path(File.join(__FILE__, '..', 'test_helper'))

class CommandTest < Test::Unit::TestCase

  def setup
    system("rm -f #{Rubber.root}/log/*.log")
    ENV['RUBBER_ROOT'] = Rubber.root
  end
  
  def teardown
    system("rm -f #{Rubber.root}/log/*.log")
  end
  
  def test_rubber_help
    out = `rubber`
    assert_match /rubber :config/, out, "help missing tasks"
    assert_match /rubber cron:sh/, out, "help missing tasks"
    assert_match /rubber util:backup/, out, "help missing tasks"
  end

  def test_rubber_cron_sh_basic
    date = Time.now.tv_sec.to_s
    out = `rubber cron:sh -- echo #{date}`

    assert_equal 0, $?
    assert_equal "", out

    logs = Dir["#{Rubber.root}/log/*.log"]
    assert_equal 1, logs.size
    assert_equal date, File.read(logs.first).strip
  end
  
  def test_rubber_cron_sh_logfile
    date = Time.now.tv_sec.to_s
    out = `rubber cron:sh -l #{Rubber.root}/log/foo.log -- echo #{date}`
    logs = Dir["#{Rubber.root}/log/*.log"]
    assert_equal 1, logs.size
    assert_equal "#{Rubber.root}/log/foo.log", logs.first
    assert_equal date, File.read(logs.first).strip
  end
  
  def test_rubber_cron_task_logfile
    date = Time.now.tv_sec.to_s
    out = `rubber cron:task -- cron:sh -o -- echo #{date}`
    logs = Dir["#{Rubber.root}/log/cron-task*.log"]
    assert_equal 1, logs.size
    assert_equal date, File.read(logs.first).strip
  end
  
  def test_rubber_cron_sh_directory_changed
    out = `rubber cron:sh -o -r /tmp -- pwd`
    assert_match /(\/private)?\/tmp/, out
  end
  
  def test_rubber_cron_sh_output_empty
    out = `rubber cron:sh -- ls -la`
    assert_equal "", out
  end

  def test_rubber_cron_sh_output_echoed
    out = `rubber cron:sh -o -- ls -la`
    assert_not_equal "", out
  end
  
  def test_rubber_cron_sh_output_on_error
    out = `rubber cron:sh -- ls -la jkbhbj`
    assert_not_equal 0, $?
    assert_not_equal "", out
  end
  
end
