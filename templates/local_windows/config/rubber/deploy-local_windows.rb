
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
