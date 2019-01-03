namespace :rubber do

  namespace :ossec do

    rubber.allow_optional_tasks(self)

    after "rubber:install_packages", "rubber:ossec:install"

    task :install, :roles => :ossec do
      rubber.sudo_script 'install_ossec', <<-ENDSCRIPT
        if ! ps -e | grep ossec &> /dev/null; then
          # Fetch the sources.
          curl --header 'Host: www.ossec.net' --header 'User-Agent: Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:31.0) Gecko/20100101 Firefox/31.0' --header 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' --header 'Accept-Language: en-US,en;q=0.5' --header 'DNT: 1' --header 'Referer: http://www.ossec.net/?page_id=19' --header 'Connection: keep-alive' 'http://www.ossec.net/files/ossec-hids-#{rubber_env.ossec_version}.tar.gz' -o 'ossec-hids-#{rubber_env.ossec_version}.tar.gz' -L
          tar -zxvf ossec-hids-#{rubber_env.ossec_version}.tar.gz
          cd ossec-hids-#{rubber_env.ossec_version}

          # Automate setup, like this one: http://ossec-docs.readthedocs.org/en/latest/manual/installation/install-source-unattended.html

          echo 'USER_LANGUAGE="en"\nUSER_NO_STOP="y"\nUSER_INSTALL_TYPE="local"\nUSER_DIR="/var/ossec"\nUSER_DELETE_DIR="y"\nUSER_ENABLE_ACTIVE_RESPONSE="y"\nUSER_ENABLE_SYSCHECK="y"\nUSER_ENABLE_ROOTCHECK="y"\nUSER_UPDATE="y"\nUSER_UPDATE_RULES="y"\nUSER_AGENT_SERVER_IP="127.0.0.1"\nUSER_AGENT_CONFIG_PROFILE="generic"\nUSER_ENABLE_EMAIL="n"\nUSER_EMAIL_ADDRESS="#{rubber_env.ossec_email}"\nUSER_ENABLE_SYSLOG="y"\nUSER_ENABLE_FIREWALL_RESPONSE="y"\nUSER_ENABLE_PF="y"\nUSER_PF_TABLE="ossec_fwtable"\nUSER_WHITE_LIST="192.168.2.1 192.168.1.0/24"\n' >> etc/preloaded-vars.conf
          # Install the binaries.
          ./install.sh -y

          # Clean up after ourselves.
          cd ..
          rm -rf ossec-hids-#{rubber_env.ossec_version}
          rm ossec-hids-#{rubber_env.ossec_version}.tar.gz
        fi
      ENDSCRIPT
    end

    after "rubber:bootstrap", "rubber:ossec:bootstrap"

    task :bootstrap, :roles => :ossec do

      # After everything installed on machines, we need the source tree
      # on hosts in order to run rubber:config for bootstrapping the db
      rubber.update_code_for_bootstrap

      # Gen just the conf for ossec.
      rubber.run_config(:file => "role/ossec", :force => true, :deploy_path => release_path)

      restart
    end

    desc "Stops the ossec server"
    task :stop, :roles => :ossec, :on_error => :continue do
      rsudo "/var/ossec/bin/ossec-control stop"
    end

    desc "Starts the ossec server"
    task :start, :roles => :ossec do

      rsudo "/var/ossec/bin/ossec-control enable client-syslog"
      rsudo "/var/ossec/bin/ossec-control start"
    end

    desc "Restarts the ossec server"
    task :restart, :roles => :ossec do
      stop
      start
    end

    desc "Reloads the ossec server"
    task :reload, :roles => :ossec do
      restart
    end

  end

end