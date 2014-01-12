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
      rubber.sudo_script "install_ruby", <<-ENDSCRIPT
      installed_ruby_ver=`which ruby | cut -d / -f 5`
      desired_ruby_ver="#{rubber_env.ruby_version}"
      if [[ ! $installed_ruby_ver =~ $desired_ruby_ver ]]; then
        echo "Compiling and installing ruby $desired_ruby_ver.  This may take a while ..."

        nohup ruby-build #{rubber_env.ruby_version} #{rubber_env.ruby_path} &> /tmp/install_ruby.log &
        bg_pid=$!
        sleep 1

        while kill -0 $bg_pid &> /dev/null; do
          echo -n .
          sleep 5
        done
        
        # this returns exit code even if pid has already died, and thus triggers fail fast shell error
        wait $bg_pid

        echo "export RUBYOPT=rubygems\nexport PATH=#{rubber_env.ruby_path}/bin:$PATH" > /etc/profile.d/ruby.sh
        echo "--- \ngem: --no-ri --no-rdoc" > /etc/gemrc
      fi
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
