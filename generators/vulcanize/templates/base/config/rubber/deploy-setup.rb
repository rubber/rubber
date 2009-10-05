namespace :rubber do
  namespace :base do
  
    rubber.allow_optional_tasks(self)


    before "rubber:install_packages", "rubber:base:pre_install_ruby"
    task :pre_install_ruby do

      # figure out which hosts we have specified enterprise ruby for
      sys_ruby_hosts = []
      ent_ruby_hosts = []
      rubber_instances.filtered.each do |ic|
        env = rubber_cfg.environment.bind(ic.role_names, ic.name)
        if env.use_enterprise_ruby
          ent_ruby_hosts << ic.full_name
        end
      end

      if ent_ruby_hosts.size > 0

        task :_install_enterprise_ruby, :hosts => ent_ruby_hosts do
          custom_package('http://rubyforge.org/frs/download.php/64479',
                         'ruby-enterprise', '1.8.7-20090928',
                         '! `ruby --version 2> /dev/null` =~ "Ruby Enterprise Edition 20090928"')
        end

        _install_enterprise_ruby
      end

    end

    #  The ubuntu rubygem package is woefully out of date, so install it manually
    after "rubber:install_packages", "rubber:base:install_rubygems"
    task :install_rubygems do
      ver = "1.3.5"
      src_url = "http://rubyforge.org/frs/download.php/60718/rubygems-#{ver}.tgz"
      rubber.sudo_script 'install_rubygems', <<-ENDSCRIPT
        if [[ `gem --version 2>&1` != "#{ver}" ]]; then
          wget -qNP /tmp #{src_url}
          tar -C /tmp -xzf /tmp/rubygems-#{ver}.tgz
          ruby -C /tmp/rubygems-#{ver} setup.rb
          ln -sf /usr/bin/gem1.8 /usr/bin/gem
          rm -rf /tmp/rubygems*
          gem source -l > /dev/null
        fi
      ENDSCRIPT
    end
    
    # git in ubuntu 7.0.4 is very out of date and doesn't work well with capistrano
    after "rubber:install_packages", "rubber:base:install_git" if scm == "git"
    task :install_git do
      rubber.run_script 'install_git', <<-ENDSCRIPT
        if ! git --version &> /dev/null; then
          arch=`uname -m`
          if [ "$arch" = "x86_64" ]; then
            src="http://mirrors.kernel.org/ubuntu/pool/main/g/git-core/git-core_1.5.4.5-1~dapper1_amd64.deb"
          else
            src="http://mirrors.kernel.org/ubuntu/pool/main/g/git-core/git-core_1.5.4.5-1~dapper1_i386.deb"
          fi
          apt-get install liberror-perl libdigest-sha1-perl
          wget -qO /tmp/git.deb ${src}
          dpkg -i /tmp/git.deb

          if [[ "#{repository}" =~ "@" ]]; then
            # Get host key for src machine to prevent ssh from failing
            rm -f ~/.ssh/known_hosts
            ! ssh -o 'StrictHostKeyChecking=no' #{repository.gsub(/:.*/, '')} &> /dev/null
          fi
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
