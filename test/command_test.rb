require File.expand_path(File.join(__FILE__, '..', 'test_helper'))

class CommandTest < Test::Unit::TestCase

  def setup
    @project_root = File.expand_path(File.join(__FILE__, '../..'))
    @rubber = "#{@project_root}/bin/rubber"
    ENV['RUBBER_ROOT'] = @project_root
  end
  
  def test_rubber_help
    out = `#{@rubber}`
    assert out =~ /Subcommands:\n(.*)\nOptions:/m
    subcommands = $1.scan(/^\s*(\S+)\s*/).flatten
    assert_equal ["config", "cron", "util:rotate_logs", "util:backup", "util:backup_db", "util:obfuscation", "util:restore_db", "vulcanize"].sort, subcommands.sort
  end

  def test_rubber_help_size
    out = `#{@rubber} --help`
    assert out.lines.all? {|l| l.size <= 81 }
    
    assert out =~ /Subcommands:\n(.*)\nOptions:/m
    subcommands = $1.scan(/^\s*(\S+)\s*/).flatten
    assert subcommands.size > 0
    subcommands.each do |s|
      out = `#{@rubber} #{s} --help`
      assert out.lines.all? {|l| l.size <= 81 }, "help for #{s} exceeds 80 chars"
    end
  
  end
  
end
