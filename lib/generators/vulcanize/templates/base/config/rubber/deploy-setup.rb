namespace :rubber do
  namespace :base do
  
    rubber.allow_optional_tasks(self)

    before "rubber:install_gems", "rubber:base:install_rvm"
    task :install_rvm do
      rubber.sudo_script "install_rvm", <<-ENDSCRIPT
        if [[ `rvm --version 2> /dev/null` == "" ]]; then
          wget -qNP /tmp http://rvm.beginrescueend.com/releases/rvm-install-head
          bash /tmp/rvm-install-head
          echo "#{rubber_env.rvm_prepare}" > /etc/profile.d/rvm.sh
          echo "rvm_prefix=/usr/local" > /etc/rvmrc
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
          rvm install $rvm_ver
          rvm use --default $rvm_ver
        fi
      ENDSCRIPT
      opts[:script_args] = '$CAPISTRANO:VAR$'
      rubber.sudo_script "install_rvm_ruby", install_rvm_ruby_script, opts
    end


    task :install_rvm_ruby_old do

      # figure out rvm versions for hosts
      rvm_ruby_hosts = {}
      rubber_instances.filtered.each do |ic|
        env = rubber_cfg.environment.bind(ic.role_names, ic.name)
        rvm_ruby_hosts[env.rvm_ruby] ||= []
        rvm_ruby_hosts[env.rvm_ruby] << ic.full_name unless ic.windows?
      end

      rvm_ruby_hosts.each do |rvm_ruby, rvm_ruby_hosts|

        task :_install_rvm_ruby, :hosts => rvm_ruby_hosts do
          rubber.sudo_script "install_rvm", <<-ENDSCRIPT
            if [[ ! `rvm list default 2> /dev/null` =~ "#{rvm_ruby}" ]]; then
              rvm install #{rvm_ruby}
              rvm use --default #{rvm_ruby}
            fi
          ENDSCRIPT
        end

        _install_rvm_ruby

      end

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
