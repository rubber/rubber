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

    task :restart, :roles => :torquebox do
      stop
      start
    end

    task :stop, :roles => :torquebox do
      rsudo "service torquebox stop || true"
    end

    task :start, :roles => :torquebox do
      rsudo "service torquebox start || true"
    end

  end
end
