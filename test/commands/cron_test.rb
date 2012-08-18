require File.expand_path(File.join(__FILE__, '../..', 'test_helper'))

class CronTest < Test::Unit::TestCase

  def setup
    system("rm -f #{Rubber.root}/log/*.log")
    ENV['RUBBER_ROOT'] = Rubber.root
  end
  
  def teardown
    system("rm -f #{Rubber.root}/log/*.log")
  end

  def test_rubber_cron_basic
    date = Time.now.tv_sec.to_s
    out = `rubber cron echo #{date}`

    assert_equal 0, $?
    assert_equal "", out

    logs = Dir["#{Rubber.root}/log/*.log"]
    assert_equal 1, logs.size
    assert_equal "#{Rubber.root}/log/cron-sh-echo.log", logs.first
    assert_match /rubber:cron running \["echo", "#{date}"\] at/, File.read(logs.first).strip
    assert_match /\n#{date}$/, File.read(logs.first).strip
  end
  
  def test_rubber_cron_log_append
    date = Time.now.tv_sec.to_s

    out = `rubber cron echo #{date}`
    assert_equal 0, $?
    assert_equal "", out

    out = `rubber cron echo #{date}`
    assert_equal 0, $?
    assert_equal "", out

    logs = Dir["#{Rubber.root}/log/*.log"]
    assert_equal 1, logs.size
    running_lines = File.read(logs.first).lines.to_a.grep(/rubber:cron running/)
    assert_equal 2, running_lines.size
  end
  
  def test_rubber_cron_logfile
    date = Time.now.tv_sec.to_s
    out = `rubber cron -l #{Rubber.root}/log/foo.log -- echo #{date}`
    logs = Dir["#{Rubber.root}/log/*.log"]
    assert_equal 1, logs.size
    assert_equal "#{Rubber.root}/log/foo.log", logs.first
    assert_match /\n#{date}$/, File.read(logs.first).strip
  end
  
  def test_rubber_cron_task_logfile
    date = Time.now.tv_sec.to_s
    out = `rubber cron --task -- cron -o -- echo #{date}`
    logs = Dir["#{Rubber.root}/log/cron-task*.log"]
    assert_equal 1, logs.size
    assert_match /\n#{date}$/, File.read(logs.first).strip
  end
  
  def test_rubber_cron_directory_changed
    out = `rubber cron -o -r /tmp -- pwd`
    assert_match /(\/private)?\/tmp/, out, "Unexpected output:\n#{out}"
  end
  
  def test_rubber_cron_output_empty
    out = `rubber cron -- ls -la`
    assert_equal "", out, "Unexpected output:\n#{out}"
  end

  def test_rubber_cron_output_echoed
    out = `rubber cron -o -- ls -la`
    assert_not_equal "", out, "Unexpected output:\n#{out}"
  end
  
  def test_rubber_cron_output_on_error
    out = `rubber cron -- ls -la jkbhbj`
    assert_not_equal 0, $?
    assert_not_equal "", out, "Unexpected output:\n#{out}"
  end
  
end
