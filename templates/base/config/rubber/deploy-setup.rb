namespace :rubber do
  namespace :base do

    rubber.allow_optional_tasks(self)

    before "rubber:setup_gem_sources", "rubber:base:install_ruby_build"
    task :install_ruby_build do
      rubber.sudo_script "install_ruby_build", <<-ENDSCRIPT
      if [[ ! `ruby-build --version 2> /dev/null` =~ "#{rubber_env.ruby_build_version}" ]]; then
        wget -q /tmp https://github.com/sstephenson/ruby-build/tarball/v#{rubber_env.ruby_build_version} -O /tmp/ruby-build.tar.gz

        # Install ruby-build.
        tar -C /tmp -zxf /tmp/ruby-build.tar.gz
        cd /tmp/sstephenson-ruby-build-*
        ./install.sh

        # Clean up after ourselves.
        cd /root
        rm -rf /tmp/sstephenson-ruby-build-*
        rm /tmp/ruby-build.tar.gz

        # Get rid of RVM if this is an older rubber installation.
        if type rvm &> /dev/null; then
          rvm implode

          rm -rf /usr/local/rvm
          rm /usr/bin/rvm*
          rm ~/.gemrc
        fi
      fi
      ENDSCRIPT
    end

    # ensure that the profile script gets sourced by reconnecting
    after "rubber:base:install_ruby_build" do
      teardown_connections_to(sessions.keys)
    end

    after "rubber:base:install_ruby_build", "rubber:base:install_ruby"
    task :install_ruby do
      rubber.sudo_script "install_ruby", <<-ENDSCRIPT
      if [[ ! `ruby --version 2> /dev/null` =~ "#{rubber_env.ruby_version}" ]]; then
        ruby-build #{rubber_env.ruby_version} #{rubber_env.ruby_path}

        echo "export RUBYOPT=rubygems\nexport PATH=#{rubber_env.ruby_path}/bin:$PATH" > /etc/profile.d/ruby.sh
        echo "--- \ngem: --no-ri --no-rdoc" > /etc/gemrc
      fi
      ENDSCRIPT
    end

    after "rubber:install_packages", "rubber:base:configure_git" if scm == "git"
    task :configure_git do
      rubber.sudo_script 'configure_git', <<-ENDSCRIPT
        if [[ "#{repository}" =~ "@" ]]; then
          # Get host key for src machine to prevent ssh from failing
          rm -f ~/.ssh/known_hosts
          ssh -o 'StrictHostKeyChecking=no' #{repository.gsub(/:.*/, '')} &> /dev/null || true
        fi
      ENDSCRIPT
    end

    # We need a rails user for safer permissions used by deploy.rb
    after "rubber:install_packages", "rubber:base:custom_install"
    task :custom_install do
      rubber.sudo_script 'custom_install', <<-ENDSCRIPT
        # add the user for running app server with
        if ! id #{rubber_env.app_user} &> /dev/null; then adduser --system --group #{rubber_env.app_user}; fi
          
        # add ssh keys for root 
        if [[ ! -f /root/.ssh/id_dsa ]]; then ssh-keygen -q -t dsa -N '' -f /root/.ssh/id_dsa; fi
      ENDSCRIPT
    end

  end
end
