namespace :rubber do

  namespace :splunk do

    namespace :client do

      rubber.allow_optional_tasks(self)

    if Rubber.env == 'production'
      after "rubber:setup_volumes", "rubber:splunk:client:install"
    end

      desc "Install Splunk"
      task :install, :roles => :splunk do
        rubber.sudo_script 'install_splunk_client', <<-ENDSCRIPT
          install_splunk ()
          {
              wget --no-check-certificate -qNP /tmp #{rubber_env.splunk_forwarder_pkg_url}
              tar -C #{rubber_env.splunk_prefix} -zxf \
                      /tmp/splunkforwarder-#{rubber_env.splunk_forwarder_version}-Linux-x86_64.tgz
              #{rubber_env.splunk_forwarder_dir}/bin/splunk start --accept-license --answer-yes --no-prompt
              #{rubber_env.splunk_forwarder_dir}/bin/splunk edit user #{rubber_env.splunk_forwarder_admin_user} \
                      -password #{rubber_env.web_tools_password} -auth #{rubber_env.splunk_forwarder_admin_user}:changeme
              #{rubber_env.splunk_forwarder_dir}/bin/splunk enable boot-start
          }

          if [ -f #{rubber_env.splunk_forwarder_dir}/bin/splunk ]; then
            if [[ "#{rubber_env.splunk_forwarder_version}" != `#{rubber_env.splunk_forwarder_dir}/bin/splunk version |awk '{print $4 "-"$6}' |sed 's/)$//' || true` ]]; then
              install_splunk
            fi
          else
            install_splunk
          fi
        ENDSCRIPT
      end

    if Rubber.env == 'production'
      after "rubber:bootstrap", "rubber:splunk:client:bootstrap"
    end

      desc "Bootstrap Splunk config"
      task :bootstrap, :roles => :splunk do
        rubber.update_code_for_bootstrap
        rubber.run_config(:file => "role/splunk", :force => true, :deploy_path => release_path)
        restart
      end

      desc "Stops Splunk forwarder"
      task :stop, :roles => :splunk, :on_error => :continue do
        rsudo "service splunk stop || true"
        rsudo "sleep 5; [[ -n \"`pgrep splunkd`\" ]] && kill -9 `pgrep splunkd`"
      end

      desc "Starts Splunk forwarder"
      task :start, :roles => :splunk do
        rsudo "service splunk start"
      end

      desc "Restarts Splunk forwarder"
      task :restart, :roles => :splunk do
        stop
        start
      end

    end

  end

end
