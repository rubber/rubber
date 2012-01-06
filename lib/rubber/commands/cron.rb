require 'open4'
require 'fileutils'

module Rubber
  module Commands

    class Cron < Thor

      namespace :cron

      # options for all tasks
      class_option :echoerr,
                   :default => false,
                   :type => :boolean, :aliases => "-e",
                   :desc => "Log _and_ echo stderr"
      class_option :echoout,
                   :default => false,
                   :type => :boolean, :aliases => "-o",
                   :desc => "Log _and_ echo stdout"
      class_option :rootdir,
                   :default => Rubber.root,
                   :type => :string, :aliases => "-r",
                   :desc => "Root dir to cd into before running"
      class_option :logfile,
                   :default => "#{Rubber.root}/log/cron-sh-#{Time.now.tv_sec}.log",
                   :type => :string, :aliases => "-l",
                   :desc => "Logs output to the given file"
      class_option :user,
                   :type => :string, :aliases => "-u",
                   :desc => "User to run the command as"

      
      desc "sh", Rubber::Util.clean_indent( <<-EOS
        Runs the given command, sending all stdout/stderr to a logfile, but echoing
        the entire file if the command exits with an error, and exits with the same
        error code the command exited with
      EOS
      )

      def sh
        cmd = parse_command
        run_command(cmd, options.logfile)
      end
            
      desc "task", Rubber::Util.clean_indent( <<-EOS
        Runs the given rubber task through cron:sh
      EOS
      )

      def task
        cmd = parse_command
        log = "#{options.rootdir}/log/cron-task-#{cmd[0]}-#{Time.now.tv_sec}.log"
        cmd = ["rubber"] + cmd
        run_command(cmd, log)
      end
      
      desc "rake", Rubber::Util.clean_indent( <<-EOS
        Runs the given rake task through cron:sh
      EOS
      )
      
      def rake
        cmd = parse_command
        log = "#{options.rootdir}/log/cron-rake-#{cmd[0]}-#{Time.now.tv_sec}.log"
        cmd = ["rake"] + cmd
        run_command(cmd, log)
      end

      desc "runner", Rubber::Util.clean_indent( <<-EOS
        Runs the given rails runner command through cron:sh
      EOS
      )
      
      def runner
        cmd = parse_command
        log = "#{options.rootdir}/log/cron-runner-#{cmd[0].gsub(/\W+/, "_")}-#{Time.now.tv_sec}.log"
        cmd = ["rails", "runner"] + cmd
        run_command(cmd, log)
      end
      
      private
      
      def parse_command
        sep_idx = ARGV.index("--")
        if sep_idx
          return ARGV[(sep_idx + 1)..-1]
        else
          fail("Run like: rubber cron:sh [opts] -- command")
        end
      end
      
      def run_command(cmd, logfile)
        if options.user
          if options.user =~ /^[0-9]+$/
            uid = options.user.to_i
          else
            uid = Etc.getpwnam(options.user).uid
          end
          Process::UID.change_privilege(uid) if uid != Process.euid
        end
        
        # make sure dir containing logfile exists
        FileUtils.mkdir_p(File.dirname(logfile))
        
        # set current directory to rootdir
        Dir.chdir(options.rootdir)
  
        status = Open4::popen4(*cmd) do |pid, stdin, stdout, stderr|
          File.open(logfile, "w") do | fh |
            threads = []
            threads <<  Thread.new(stdout) do |stdout|
               stdout.each { |line| $stdout.puts line if options.echoout; fh.print line; fh.flush }
            end
            threads <<  Thread.new(stderr) do |stderr|
               stderr.each { |line| $stderr.puts line if options.echoerr; fh.print line; fh.flush }
            end
            threads.each { |t| t.join }
          end
        end
        
        result = status.exitstatus
        if result != 0
          puts ""
          puts "*** Process exited with non-zero error code, full output follows"
          puts "*** Command was: #{cmd.join(' ')}"
          puts ""
          puts IO.read(logfile)
        end
        
        exit(result)
      end
    
    end
    
  end
end
