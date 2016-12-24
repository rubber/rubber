namespace :rubber do

  namespace :logstash do

    rubber.allow_optional_tasks(self)

    namespace :agent do

      rubber.allow_optional_tasks(self)

      before "rubber:install_packages", "rubber:logstash:agent:setup_apt_sources"

      task :setup_apt_sources, :roles => :logstash_agent do
        rubber.sudo_script 'configure_rsyslog_repository', <<-ENDSCRIPT
          # Remove old repo
          echo "It is safe to ignore errors about ubuntu.adiscon.com repos not existing in sourcelist."
          add-apt-repository --remove "deb http://ubuntu.adiscon.com/v7-stable precise/" || true

          # Add current repo
          #add-apt-repository --yes ppa:adiscon/v7-stable
          apt-key adv --recv-keys --keyserver keyserver.ubuntu.com AEF0CF8E
          #gpg --export --armor AEF0CF8E | sudo apt-key add -
          add-apt-repository --yes "deb http://ppa.launchpad.net/adiscon/v7-stable/ubuntu precise main"
        ENDSCRIPT
      end

    end

    namespace :server do

      rubber.allow_optional_tasks(self)

      after "rubber:install_packages", "rubber:logstash:server:install"

      task :install, :roles => :logstash_server do
        rubber.sudo_script 'install_logstash', <<-ENDSCRIPT
          if [[ ! -d "#{rubber_env.logstash_dir}" ]]; then
            mkdir -p #{rubber_env.logstash_dir}
            wget --no-check-certificate -qNP #{rubber_env.logstash_dir} #{rubber_env.logstash_pkg_url}
          fi
        ENDSCRIPT
      end

      after "rubber:bootstrap", "rubber:logstash:server:bootstrap"

      task :bootstrap, :roles => :logstash_server do
        exists = capture("echo $(ls #{rubber_env.logstash_server_conf} 2> /dev/null)")
        if exists.strip.size == 0
          # After everything installed on machines, we need the source tree
          # on hosts in order to run rubber:config for bootstrapping the db
          rubber.update_code_for_bootstrap
          rubber.run_config(:file => "role/logstash_server/", :force => true, :no_post => true, :deploy_path => release_path)

          restart
        end
      end

      task :start, :roles => :logstash_server do
        rsudo "service logstash-server start"
        rsudo "service rsyslog restart"
      end

      task :stop, :roles => :logstash_server do
        rsudo "service logstash-server stop || true"
      end

      task :restart, :roles => :logstash_server do
        stop
        start
      end

    end
  end
end
