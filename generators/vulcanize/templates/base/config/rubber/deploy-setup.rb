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

          # preferences to pick up specific Ruby packages from brightbox
          prefs = <<-DATA
            Package: *
            Pin: release l=brightbox
            Pin-Priority: 1001

            Package: ruby1.8-elisp
            Pin: release l=Ubuntu
            Pin-Priority: 1001
          DATA

          prefs.gsub!(/^ */, '') # remove leading whitespace
          put(prefs, '/etc/apt/preferences')

          rubber.sudo_script 'install_enterprise_ruby', <<-ENDSCRIPT
            wget http://apt.brightbox.net/release.asc -O - | apt-key add -
            echo "deb http://apt.brightbox.net/ hardy rubyee" > /etc/apt/sources.list.d/brightbox-rubyee.list
          ENDSCRIPT

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
          wget -qP /tmp #{src_url}
          tar -C /tmp -xzf /tmp/rubygems-#{ver}.tgz
          ruby -C /tmp/rubygems-#{ver} setup.rb
          ln -sf /usr/bin/gem1.8 /usr/bin/gem
          rm -rf /tmp/rubygems*
          gem source -l > /dev/null
          gem sources -a http://gems.github.com
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
        # add the rails user for running app server with
        appuser="rails"
        if ! id ${appuser} &> /dev/null; then adduser --system --group ${appuser}; fi
          
        # add ssh keys for root 
        if [[ ! -f /root/.ssh/id_dsa ]]; then ssh-keygen -q -t dsa -N '' -f /root/.ssh/id_dsa; fi
      ENDSCRIPT
    end

  end
end
