namespace :rubber do
  namespace :base do
  
    rubber.allow_optional_tasks(self)

    before "rubber:setup_gem_sources", "rubber:base:install_rvm"
    task :install_rvm do
      rubber.sudo_script "install_rvm", <<-ENDSCRIPT
        if [[ ! `rvm --version 2> /dev/null` =~ "#{rubber_env.rvm_version}" ]]; then
          cd /tmp
          curl -s https://raw.github.com/wayneeseguin/rvm/master/binscripts/rvm-installer -o rvm-installer
          chmod +x rvm-installer
          rm -f /etc/rvmrc
          rvm_path=#{rubber_env.rvm_prefix} ./rvm-installer --version #{rubber_env.rvm_version}

          # Set up the rubygems version
          sed -i 's/rubygems_version=.*/rubygems_version=#{rubber_env.rubygems_version}/' #{rubber_env.rvm_prefix}/config/db

          # Set up the rake version
          sed -i 's/rake.*/rake -v#{rubber_env.rake_version}/' #{rubber_env.rvm_prefix}/gemsets/default.gems
          sed -i 's/rake.*/rake -v#{rubber_env.rake_version}/' #{rubber_env.rvm_prefix}/gemsets/global.gems

          # Set up the .gemrc file
          if [[ ! -f ~/.gemrc ]]; then
            echo "--- " >> ~/.gemrc
          fi

          if ! grep -q 'gem: ' ~/.gemrc; then
            echo "gem: --no-ri --no-rdoc" >> ~/.gemrc
          fi
        fi
      ENDSCRIPT
    end

    # ensure that the rvm profile script gets sourced by reconnecting
    after "rubber:base:install_rvm" do
      teardown_connections_to(sessions.keys)
    end

    after "rubber:base:install_rvm", "rubber:base:install_rvm_ruby"
    task :install_rvm_ruby do
      opts = get_host_options('rvm_ruby')
      
      # sudo_script only takes a single hash with host -> VAR, so combine our
      # two vars so we can extract them out in the bash script
      install_opts = get_host_options('rvm_install_options')
      install_opts.each do |k, v|
        opts[k] = "#{opts[k]} #{v}"
      end
      
      install_rvm_ruby_script = <<-ENDSCRIPT
        rvm_ver=$1
        shift
        install_opts=$*

        if [[ ! `rvm list default 2> /dev/null` =~ "$rvm_ver" ]]; then
          echo "RVM is compiling/installing ruby $rvm_ver, this may take a while"

          nohup rvm install $rvm_ver $install_opts &> /tmp/install_rvm_ruby.log &
          sleep 1

          while true; do
            if ! ps ax | grep -q "[r]vm install"; then break; fi
            echo -n .
            sleep 5
          done

          # need to set default after using once or something in env is broken
          rvm use $rvm_ver &> /dev/null
          rvm use $rvm_ver --default

          # Something flaky with $PATH having an entry for "bin" which breaks
          # munin, the below seems to fix it
          rvm use $rvm_ver
          rvm repair environments
          rvm use $rvm_ver
        fi
      ENDSCRIPT
      opts[:script_args] = '$CAPISTRANO:VAR$'
      rubber.sudo_script "install_rvm_ruby", install_rvm_ruby_script, opts
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

  end
end
