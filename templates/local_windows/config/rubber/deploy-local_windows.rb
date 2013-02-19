
on :load do

  if rubber_env.local_windows? && rubber_instances.reject{|i| i.windows?}.any?

    # The Bundler 'platforms' block in your Gemfile currently causes cross-platform
    # deploys to fail. See: https://github.com/carlhuda/bundler/issues/646
    # As a workaround we deploy to remote Linux without the Gemfile.lock from Windows.
    # If you are not using 'platforms' in your Gemfile, you do not need this hack.
    set :copy_exclude, strategy.copy_exclude + ['Gemfile.lock']
    set :bundle_flags, "--quiet"

    # An alternative option for the above limitation:
    # set :bundle_flags, "--no_deployment --quiet"

  end

end
