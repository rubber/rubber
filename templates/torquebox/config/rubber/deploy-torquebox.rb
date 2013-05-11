namespace :rubber do

  namespace :torquebox do

    rubber.allow_optional_tasks(self)

    after "rubber:install_packages", "rubber:torquebox:custom_install"

    task :custom_install, :roles => :torquebox do
      rubber.sudo_script 'install_torquebox', <<-ENDSCRIPT
        if [[ -z `ls #{rubber_env.torquebox_prefix}/torquebox-#{rubber_env.torquebox_version} 2> /dev/null` ]]; then
          wget -q http://torquebox.org/release/org/torquebox/torquebox-dist/#{rubber_env.torquebox_version}/torquebox-dist-#{rubber_env.torquebox_version}-bin.zip
          unzip -d #{rubber_env.torquebox_prefix} torquebox-dist-#{rubber_env.torquebox_version}-bin.zip &> /dev/null
          chown -R #{rubber_env.app_user} #{rubber_env.torquebox_prefix}/torquebox-#{rubber_env.torquebox_version}

          # Install to appropriate location.
          rm -f #{rubber_env.torquebox_dir}
          ln -s #{rubber_env.torquebox_prefix}/torquebox-#{rubber_env.torquebox_version} #{rubber_env.torquebox_dir}

          # Create the log dir.
          mkdir -p #{rubber_env.torquebox_log_dir}
          chown -R #{rubber_env.app_user} #{rubber_env.torquebox_log_dir}

          # Set up libraries for graylog logger.
          mkdir -p #{rubber_env.torquebox_dir}/jboss/modules/org/graylog2/logging/main
          wget -qNO "#{rubber_env.torquebox_dir}/jboss/modules/org/graylog2/logging/main/gelfj-1.0.1.jar" https://github.com/downloads/t0xa/gelfj/gelfj-1.0.1.jar
          wget -qNO "#{rubber_env.torquebox_dir}/jboss/modules/org/graylog2/logging/main/json-simple-1.1.1.jar" http://json-simple.googlecode.com/files/json-simple-1.1.1.jar

          # Cleanup after ourselves.
          rm torquebox-dist-#{rubber_env.torquebox_version}-bin.zip
        fi
      ENDSCRIPT
    end

    after "rubber:install_packages", "rubber:torquebox:install_mod_cluster"

    task :install_mod_cluster, :roles => :app do
      rubber.sudo_script 'install_mod_cluster', <<-ENDSCRIPT
        if [[ ! -f /usr/lib/apache2/modules/mod_proxy_cluster.so ]]; then
          wget -q http://downloads.jboss.org/mod_cluster/#{rubber_env.mod_cluster_version}.Final/mod_cluster-#{rubber_env.mod_cluster_version}.Final-linux2-x64-so.tar.gz
          tar -zxf mod_cluster-#{rubber_env.mod_cluster_version}.Final-linux2-x64-so.tar.gz

          # Install to appropriate locations
          chmod 644 mod_*.so
          mv mod_*.so /usr/lib/apache2/modules/

          # Cleanup after ourselves.
          rm mod_cluster-#{rubber_env.mod_cluster_version}.Final-linux2-x64-so.tar.gz
        fi
      ENDSCRIPT
    end

    # serial_task can only be called after roles defined - not normally a problem, but
    # rubber auto-roles don't get defined till after all tasks are defined
    on :load do
      rubber.serial_task self, :serial_reload, :roles => [:torquebox] do
        rsudo "touch #{jboss_home}/standalone/deployments/#{application}-knob.yml.dodeploy"
        rsudo "if ! ps ax | grep -v grep | grep -c torque &> /dev/null; then service torquebox start; fi"

        # Wait for TorqueBox to startup before moving on so we don't remove all hosts from the cluster.
        logger.info "Waiting for TorqueBox to deploy"

        # TorqueBox first "deploys" the app, then lets the web context startup.  While it's deploying,
        # the old context can still service requests.  So, we need to wait until the app is deployed before we can
        # start checking if it's handling web requests.  Once it's deployed and web requests are being served we can move on.
        rsudo "while ls #{jboss_home}/standalone/deployments/#{application}-knob.yml.dodeploy &> /dev/null; do echo .; sleep 1; done"
        rsudo "while ! curl -s -f http://$HOSTNAME:#{rubber_env.torquebox_http_port} &> /dev/null; do echo .; sleep 1; done"
      end
    end

    after "rubber:deploy:cold", "rubber:torquebox:install_backstage"

    task :install_backstage, :roles => :app do
      rsudo "backstage deploy --secure=#{rubber_env.backstage_user}:#{rubber_env.backstage_password}"
    end

    after "rubber:setup_app_permissions", "rubber:torquebox:setup_app_permissions"

    task :setup_app_permissions do
      rsudo "chown -R #{rubber_env.app_user}:#{rubber_env.app_user} #{current_path}/public"
      rsudo "chown -R #{rubber_env.app_user}:#{rubber_env.app_user} #{current_path}/tmp"
    end

    before "deploy:finalize_update", "rubber:torquebox:create_cache_directory"

    task :create_cache_directory do
      rsudo "mkdir #{shared_path}/cache || true"
      rsudo "chown -R #{rubber_env.app_user}:#{rubber_env.app_user} #{shared_path}/cache"
    end

    before "deploy:stop", "rubber:torquebox:stop"
    after "deploy:start", "rubber:torquebox:start"
    after "deploy:restart", "rubber:torquebox:reload"

    task :restart, :roles => :torquebox do
      stop
      start
    end

    task :stop, :roles => :torquebox do
      rsudo "service torquebox stop || true"
    end

    task :start, :roles => :torquebox do
      rsudo "service torquebox start"
    end

    desc "Reloads the apache web server"
    task :reload, :roles => :torquebox do
      serial_reload
    end

  end
end
