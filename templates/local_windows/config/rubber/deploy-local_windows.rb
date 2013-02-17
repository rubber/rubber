
on :load do

  if rubber_env.local_windows? && rubber_instances.reject{|i| i.windows?}.any?

    # Bundler has a known feature limitation that the Bundler 'platforms'
    # Gemfile block does not work across platforms, as a Gemfile.lock
    # generated on Windows is enforced strictly on Linux.
    # See: https://github.com/carlhuda/bundler/issues/646

    # If you are not using 'platforms' in your Gemfile, you do not need this hack.
    # Otherwise, you have two options:

    # Option 1) exclude Gemfile.lock from the Bundle transfer (Heroku does this)
    set :copy_exclude, strategy.copy_exclude + ['Gemfile.lock']

    # Option 2) tell Bunder to disregard Gemfile.lock on the remote server
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

    task :dos2unix_code, :except => { :no_release => true, :platform => 'windows' } do
      rsudo "find #{release_path} -type f -exec dos2unix -q {} \\;"
    end

  end

end