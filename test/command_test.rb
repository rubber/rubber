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
    assert out =~ /Subcommands:\n(.*)\nOptions:/m
    subcommands = $1.scan(/^\s*(\S+)\s*/).flatten
    assert_equal ["config", "cron", "util:rotate_logs", "util:backup", "util:backup_db", "util:restore_db_s3", "vulcanize"], subcommands
  end

  def test_rubber_help_size
    out = `rubber --help`
    assert out.lines.all? {|l| l.size <= 81 }
    
    assert out =~ /Subcommands:\n(.*)\nOptions:/m
    subcommands = $1.scan(/^\s*(\S+)\s*/).flatten
    assert subcommands.size > 0
    subcommands.each do |s|
      out = `rubber #{s} --help`
      assert out.lines.all? {|l| l.size <= 81 }, "help for #{s} exceeds 80 chars"
    end
  
  end

  def test_rubber_cron_basic
    date = Time.now.tv_sec.to_s
    out = `rubber cron echo #{date}`

    assert_equal 0, $?
    assert_equal "", out

    logs = Dir["#{Rubber.root}/log/*.log"]
    assert_equal 1, logs.size
    assert_equal date, File.read(logs.first).strip
  end
  
  def test_rubber_cron_logfile
    date = Time.now.tv_sec.to_s
    out = `rubber cron -l #{Rubber.root}/log/foo.log -- echo #{date}`
    logs = Dir["#{Rubber.root}/log/*.log"]
    assert_equal 1, logs.size
    assert_equal "#{Rubber.root}/log/foo.log", logs.first
    assert_equal date, File.read(logs.first).strip
  end
  
  def test_rubber_cron_task_logfile
    date = Time.now.tv_sec.to_s
    out = `rubber cron --task -- cron -o -- echo #{date}`
    logs = Dir["#{Rubber.root}/log/cron-task*.log"]
    assert_equal 1, logs.size
    assert_equal date, File.read(logs.first).strip
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
