namespace :rubber do
  namespace :base do
  
    rubber.allow_optional_tasks(self)

    before "rubber:setup_gem_sources", "rubber:base:install_rvm"
    task :install_rvm do
      rubber.sudo_script "install_rvm", <<-ENDSCRIPT
        if [[ ! `rvm --version 2> /dev/null` =~ "#{rubber_env.rvm_version}" ]]; then
          echo "rvm_prefix=/usr/local/" > /etc/rvmrc
          echo "#{rubber_env.rvm_prepare}" > /etc/profile.d/rvm.sh

          # Copied below from http://rvm.beginrescueend.com/releases/rvm-install-latest
          #

          if [[ -f /etc/rvmrc ]] ; then source /etc/rvmrc ; fi

          if [[ -f "$HOME/.rvmrc" ]] ; then source "$HOME/.rvmrc" ; fi

          rvm_path="${rvm_path:-$HOME/.rvm}"

          mkdir -p $rvm_path/src/

          builtin cd $rvm_path/src

          stable_version=#{rubber_env.rvm_version}

          echo "rvm-${stable_version}"

          curl -L "http://rvm.beginrescueend.com/releases/rvm-${stable_version}.tar.gz" -o "rvm-${stable_version}.tar.gz"

          tar zxf "rvm-${stable_version}.tar.gz"

          builtin cd "rvm-${stable_version}"

          dos2unix scripts/* >/dev/null 2>&1 || true

          bash ./scripts/install

          sed -i 's/rubygems_version=.*/rubygems_version=#{rubber_env.rubygems_version}/' #{rubber_env.rvm_prefix}/config/db

          #
          # end rvm install script

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
      install_rvm_ruby_script = <<-ENDSCRIPT
        rvm_ver=$1
        if [[ ! `rvm list default 2> /dev/null` =~ "$rvm_ver" ]]; then
          echo "RVM is compiling/installing ruby $rvm_ver, this may take a while"

          nohup rvm install $rvm_ver &> /tmp/install_rvm_ruby.log &
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
          ! ssh -o 'StrictHostKeyChecking=no' #{repository.gsub(/:.*/, '')} &> /dev/null
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
