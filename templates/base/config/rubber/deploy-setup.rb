namespace :rubber do
  namespace :base do

    rubber.allow_optional_tasks(self)

    before "rubber:setup_gem_sources", "rubber:base:install_ruby_build"
    task :install_ruby_build do
      rubber.sudo_script "install_ruby_build", <<-ENDSCRIPT
      if [[ ! `ruby-build --version 2> /dev/null` =~ "#{rubber_env.ruby_build_version}" ]]; then
        echo "Installing ruby-build v#{rubber_env.ruby_build_version}"
        wget -q https://github.com/sstephenson/ruby-build/archive/v#{rubber_env.ruby_build_version}.tar.gz -O /tmp/ruby-build.tar.gz

        # Install ruby-build.
        tar -C /tmp -zxf /tmp/ruby-build.tar.gz
        cd /tmp/ruby-build-*
        ./install.sh

        # Clean up after ourselves.
        cd /root
        rm -rf /tmp/ruby-build-*
        rm -f /tmp/ruby-build.tar.gz

        # Get rid of RVM if this is an older rubber installation.
        if type rvm &> /dev/null; then
          echo -en "yes\n" | rvm implode

          rm -rf /usr/local/rvm
          rm -f /usr/bin/rvm*
          rm -f ~/.gemrc
        fi
      fi
      ENDSCRIPT
    end

    after "rubber:base:install_ruby_build", "rubber:base:install_ruby"
    task :install_ruby do
      rubber_env.ruby_versions.each do |ruby_version|
        ruby_path = File.join(rubber_env.base_ruby_path, ruby_version)

        rubber.sudo_script "install_ruby_#{ruby_version}", <<-ENDSCRIPT
        if [[ ! -d #{ruby_path} ]]; then
          echo "Compiling and installing ruby #{ruby_version}.  This may take a while ..."

          nohup ruby-build #{ruby_version} #{ruby_path} &> /tmp/install_ruby_#{ruby_version}.log &
          sleep 1

          while true; do
            if ! ps ax | grep -q "[r]uby-build"; then break; fi
            echo -n .
            sleep 5
          done
        fi

        if [[ ! -d #{ruby_path} ]]; then
          echo "Failed to install #{ruby_version}.  Please see /tmp/install_ruby_#{ruby_version}.log for more details."

          # Return an error status for the script.
          false
        fi
        ENDSCRIPT
      end

      default_ruby_path = File.join(rubber_env.base_ruby_path, rubber_env.default_ruby_version)
      rubber.sudo_script "setup_ruby", <<-ENDSCRIPT
      echo "export RUBYOPT=rubygems" > /etc/profile.d/ruby.sh
      echo "export RUBY_VERSION=\\${RUBY_VERSION:=#{rubber_env.default_ruby_version}}" >> /etc/profile.d/ruby.sh
      echo "export PATH=#{rubber_env.base_ruby_path}/\\$RUBY_VERSION/bin:\\$PATH" >> /etc/profile.d/ruby.sh
      echo "export JRUBY_OPTS=\\"--1.9 -Xcext.enabled=true\\"" >> /etc/profile.d/ruby.sh
      echo "--- \ngem: --no-ri --no-rdoc" > /etc/gemrc
      ENDSCRIPT
    end
    
    # ensure that the profile script gets sourced by reconnecting
    after "rubber:base:install_ruby" do
      teardown_connections_to(sessions.keys)
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

    # Update /etc/sudoers so that SSH-related environment variables so capistrano/rubber tasks can take advantage of ssh-agent forwarding
    before "rubber:bootstrap", "rubber:base:update_sudoers"
    task :update_sudoers do
      rubber.sudo_script "update_sudoers", <<-ENDSCRIPT
        if [[ ! `grep 'SSH_CLIENT SSH_TTY SSH_CONNECTION SSH_AUTH_SOCK' /etc/sudoers` =~ "SSH_CLIENT SSH_TTY SSH_CONNECTION SSH_AUTH_SOCK" ]]; then
          echo '' >> /etc/sudoers
          echo '# whitelist SSH-related environment variables so capistrano tasks can take advantage of ssh-agent forwarding' >> /etc/sudoers
          echo 'Defaults env_keep += "SSH_CLIENT SSH_TTY SSH_CONNECTION SSH_AUTH_SOCK"' >> /etc/sudoers
        fi
      ENDSCRIPT
    end

    after "rubber:bootstrap", "rubber:base:reinstall_virtualbox_additions"
    task :reinstall_virtualbox_additions, :only => { :provider => 'vagrant' } do
      rsudo "service vboxadd setup"
    end
  end
end
