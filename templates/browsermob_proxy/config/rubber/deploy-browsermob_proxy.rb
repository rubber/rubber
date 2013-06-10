namespace :rubber do

  namespace :browsermob_proxy do

    rubber.allow_optional_tasks(self)

    after "rubber:install_packages", "rubber:browsermob_proxy:install"

    task :install, :roles => :browsermob_proxy do
      rubber.sudo_script 'install_browsermob_proxy', <<-ENDSCRIPT
      # Create the log directory if necessary.
      if [[ ! -d #{rubber_env.browsermob_proxy_log_dir} ]]; then
        mkdir -p #{rubber_env.browsermob_proxy_log_dir}
        chown app:app #{rubber_env.browsermob_proxy_log_dir}
      fi      

      if [[ ! -d #{rubber_env.browsermob_proxy_dir} ]]; then
        cd /tmp
        wget -q https://s3-us-west-1.amazonaws.com/lightbody-bmp/browsermob-proxy-#{rubber_env.browsermob_proxy_version}-bin.zip
        unzip browsermob-proxy-#{rubber_env.browsermob_proxy_version}-bin.zip

        mv browsermob-proxy-#{rubber_env.browsermob_proxy_version} #{rubber_env.browsermob_proxy_dir}
        chmod +x #{rubber_env.browsermob_proxy_dir}/bin/browsermob-proxy

        rm browsermob-proxy-#{rubber_env.browsermob_proxy_version}-bin.zip
      fi
      ENDSCRIPT
    end

    after "rubber:bootstrap", "rubber:browsermob_proxy:bootstrap"

    task :bootstrap, :roles => :browsermob_proxy do
      # After everything installed on machines, we need the source tree
      # on hosts in order to run rubber:config for bootstrapping the db
      rubber.update_code_for_bootstrap

      # Gen just the conf for cassandra
      rubber.run_config(:file => "role/browsermob_proxy", :force => true, :deploy_path => release_path)
    end

    after "rubber:setup_app_permissions", "rubber:browsermob_proxy:setup_permissions"

    task :setup_permissions, :roles => :browsermob_proxy do
      rsudo "chown -R #{rubber_env.app_user}:#{rubber_env.app_user} #{rubber_env.browsermob_proxy_dir}"
    end

    task :restart, :roles => :browsermob_proxy do
      stop
      start
    end

    task :stop, :roles => :browsermob_proxy, :on_error => :continue do
      rsudo "cat #{rubber_env.browsermob_proxy_dir}/browsermob_proxy.pid | xargs kill; exit 0"
    end

    task :start, :roles => :browsermob_proxy do
      rsudo "#{rubber_env.browsermob_proxy_dir}/startup.sh"
    end

    after "rubber:create", "rubber:setup_dns_records"
  end

end
