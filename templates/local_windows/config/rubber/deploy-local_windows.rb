
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

namespace :rubber do

  namespace :local_windows do

    # Run dos2unix on code only if it has been deployed via copy
    if ENV.has_key?('FIX_LINE_ENDINGS') || (Rubber.config.local_windows? && (fetch(:deploy_via, nil) == :copy))
      after "deploy:update_code", "rubber:local_windows:dos2unix_code"
    end

    # Always run dos2unix each time config is pushed, as the Rubber secret file is always pushed via copy
    if ENV.has_key?('FIX_LINE_ENDINGS') || Rubber.config.local_windows?
      after "rubber:config:push", "rubber:local_windows:dos2unix_config"
    end

    desc <<-DESC
      Converts remote code files to Windows-style line endings (CR+LF) to Unix-style (LF)
    DESC
    task :dos2unix_code, :except => { :platform => 'windows' } do
      run_dos2unix release_path
    end

    desc <<-DESC
      Converts remote config files to Windows-style line endings (CR+LF) to Unix-style (LF)
    DESC
    task :dos2unix_config, :except => { :platform => 'windows' } do
      run_dos2unix config_path
    end

    def run_dos2unix(path)
      rsudo "find #{path} -type f -exec dos2unix -q {} \\;"
    end

    def config_path
      File.join(release_path, rubber_cfg.environment.config_root.sub(/^#{Rubber.root}\/?/, ''))
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
