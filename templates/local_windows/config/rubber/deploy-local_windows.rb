
on :load do

  if rubber_env.local_windows? && rubber_instances.reject{|i| i.windows?}.any?

    # The Bundler 'platforms' block in your Gemfile currently causes cross-platform
    # deploys to fail. See: https://github.com/carlhuda/bundler/issues/646
    # As a workaround we deploy to remote Linux without the Gemfile.lock from Windows.
    # If you are not using 'platforms' in your Gemfile, you do not need this hack.
    set :copy_exclude, strategy.copy_exclude + ['Gemfile.lock']
    set :bundle_flags, "--quiet"

    # An alternative option:
    # set :bundle_flags, "--no_deployment --quiet"

  end

end

after "deploy:update_code", "deploy:local_windows:dos2unix_code"

namespace :deploy do

  namespace :local_windows do

    desc <<-DESC
      Converts Windows-style line endings (CR+LF) to Unix-style (LF)
      after code has been copied to remote server.
    DESC

    task :dos2unix_code, :except => { :platform => 'windows' } do
      rsudo "find #{release_path} -type f -exec dos2unix -q {} \\;" if rubber_env.use_dos2unix
    end

  end

end

namespace :rubber do

  namespace :putty do

    desc <<-DESC
      Opens Putty sessions with your servers. Open multiple sessions at once
      with FILTER variable. Requires Putty in your system path and a key
      named *.ppk in your keys directory.
    DESC
    task :default do
      rubber_env.rubber_instances.filtered.each do |inst|
        # can use rubber_env.cloud_providers.aws.key_file as well
        spawn("putty -ssh ubuntu@#{inst.external_host} -i #{Rubber.cloud.env.key_file}.ppk")
      end
    end

  end

end
