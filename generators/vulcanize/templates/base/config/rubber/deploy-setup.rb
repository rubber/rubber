#  The ubuntu rubygem package is woefully out of date, so install it manually
after "rubber:install_packages", "rubber_install_rubygems"
task :rubber_install_rubygems do
  ver = "1.2.0"
  rubber.sudo_script 'install_rubygems', <<-ENDSCRIPT
    if [ ! -f /usr/bin/gem ]; then
      wget -qP /tmp http://rubyforge.org/frs/download.php/38646/rubygems-#{ver}.tgz
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
after "rubber:install_packages", "rubber_install_git" if scm == "git"
task :rubber_install_git do
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
    fi
  ENDSCRIPT
end

# We need a rails user for safer permissions used by deploy.rb
after "rubber:install_packages", "custom_install_base"
task :custom_install_base do
  # add the rails user for running app server with
  appuser = "rails"
  run "if ! id #{appuser} &> /dev/null; then adduser --system --group #{appuser}; fi"
end

