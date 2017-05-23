require 'open3'
require 'fileutils'

module Rubber
  module Commands

    class Cron < Clamp::Command

      def self.subcommand_name
        "cron"
      end

      def self.subcommand_description
        "A cron-safe way for running commands"
      end
      
      def self.description
        Rubber::Util.clean_indent( <<-EOS
          Runs the given command, sending all stdout/stderr to a logfile, but echoing
          the entire file if the command exits with an error.  Exits with the same
          error code the command exited with
        EOS
        )
      end
      
      # options for all tasks
      option ["-e", "--echoerr"],
             :flag,
             "Log _and_ echo stderr",
             :default => false
      option ["-o", "--echoout"],
             :flag,
             "Log _and_ echo stdout",
             :default => false
      option ["-r", "--rootdir"],
             "ROOTDIR",
             "Root dir to cd into before running\n (default: <Rubber.root>)"
      option ["-l", "--logfile"],
             "LOGFILE",
             "Logs output to the given file\n (default: <rootdir>/log/cron-sh-<time>.log)"
      option ["-u", "--user"],
             "USER",
             "User to run the command as"
      option ["--task"],
             :flag,
             "Run the arguments with rubber"
      option ["--ruby"],
             :flag,
             "Run the arguments with ruby"
      option ["--runner"],
             :flag,
             "Run the arguments with rails runner"
      option ["--rake"],
             :flag,
             "Run the arguments with rake"
      parameter "COMMAND ...", "the command to run"

      def execute
        cmd = command_list
        self.rootdir ||= Rubber.root
        ident = cmd[0].gsub(/\W+/, "_").gsub(/(^_+)|(_+$)/, '')[0..19]
        self.logfile ||= "#{Rubber.root}/log/cron-sh-#{ident}.log"
        log = logfile
        
        if task?
          log = "#{rootdir}/log/cron-task-#{ident}.log"
          cmd = [$0] + cmd
        elsif ruby?
          ruby_code = cmd.join(' ')
          ident = ruby_code.gsub(/\W+/, "_").gsub(/(^_+)|(_+$)/, '')[0..19]
          log = "#{rootdir}/log/cron-ruby-#{ident}.log"
          cmd = ["ruby", "-e", ruby_code]
        elsif runner?
          log = "#{rootdir}/log/cron-runner-#{ident}.log"
          cmd = ["rails", "runner"] + cmd
        elsif rake?
          log = "#{rootdir}/log/cron-rake-#{ident}.log"
          cmd = ["rake"] + cmd
        end
        
        if user
          if user =~ /^[0-9]+$/
            uid = user.to_i
          else
            uid = Etc.getpwnam(user).uid
          end
          Process::UID.change_privilege(uid) if uid != Process.euid
        end
        
        # make sure dir containing logfile exists
        FileUtils.mkdir_p(File.dirname(log))
        
        # set current directory to rootdir
        Dir.chdir(rootdir)

        status = Open3.popen3(*cmd) do |stdin, stdout, stderr, wait_thread|
          File.open(log, "a") do | fh |
            fh.puts "\nrubber:cron running #{cmd.inspect} at #{Time.now}\n"
            threads = []

            threads <<  Thread.new(stdout) do |stdout|
              stdout.each { |line| $stdout.puts line if echoout?; fh.print line; fh.flush }
            end

            threads <<  Thread.new(stderr) do |stderr|
              stderr.each { |line| $stderr.puts line if echoerr?; fh.print line; fh.flush }
            end

            threads.each { |t| t.join }
          end

          wait_thread.value
        end

        result = status.exitstatus
        if result != 0
          puts ""
          puts "*** Process exited with non-zero error code, full output follows"
          puts "*** Command was: #{cmd.join(' ')}"
          puts ""
          puts IO.read(log)
        end
        
        exit(result)
      end
    
    end
    
  end
end
