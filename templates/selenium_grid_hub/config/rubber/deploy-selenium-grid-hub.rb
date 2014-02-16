namespace :rubber do

  namespace :selenium_grid do

    rubber.allow_optional_tasks(self)

    namespace :hub do
      rubber.allow_optional_tasks(self)

      after "rubber:install_packages", "rubber:selenium_grid:hub:install"

      task :install, :roles => :selenium_grid_hub do
        rubber.sudo_script 'install_selenium_grid_hub', <<-ENDSCRIPT
        # Create the log directory if necessary.
        if [[ ! -d #{rubber_env.selenium_grid_hub_log_dir} ]]; then
          mkdir -p #{rubber_env.selenium_grid_hub_log_dir}
          chown #{rubber_env.app_user}:#{rubber_env.app_user} #{rubber_env.selenium_grid_hub_log_dir}
        fi

        if [[ ! -d #{rubber_env.selenium_grid_hub_dir} ]]; then
          mkdir -p #{rubber_env.selenium_grid_hub_dir}
          chown #{rubber_env.app_user}:#{rubber_env.app_user} #{rubber_env.selenium_grid_hub_dir}
        fi

        # Fetch the Selenium Grid 2 JARs.
        wget -q https://selenium.googlecode.com/files/selenium-server-standalone-#{rubber_env.selenium_grid_hub_version}.jar -O #{rubber_env.selenium_grid_hub_dir}/selenium-server-standalone-#{rubber_env.selenium_grid_hub_version}.jar

        # Fetch the Graylog2 logging JARs.
        wget -q http://files-staging.mogotest.com.s3.amazonaws.com/gelfj-1.0.jar -O #{rubber_env.selenium_grid_hub_dir}/gelfj.jar
        wget -q http://files-staging.mogotest.com.s3.amazonaws.com/json-simple-1.1.jar -O #{rubber_env.selenium_grid_hub_dir}/json-simple.jar
        ENDSCRIPT
      end

      after "rubber:bootstrap", "rubber:selenium_grid:hub:bootstrap"

      task :bootstrap, :roles => :selenium_grid_hub do
        # After everything installed on machines, we need the source tree
        # on hosts in order to run rubber:config for bootstrapping the db
        rubber.update_code_for_bootstrap

        # Gen just the conf for cassandra
        rubber.run_config(:file => "role/selenium_grid_hub", :force => true, :deploy_path => release_path)
      end

      after "rubber:setup_app_permissions", "rubber:selenium_grid:hub:setup_permissions"

      task :setup_permissions, :roles => :selenium_grid_hub do
        rsudo "chown -R #{rubber_env.app_user}:#{rubber_env.app_user} #{rubber_env.selenium_grid_hub_dir}"
      end

      task :restart, :roles => :selenium_grid_hub do
        stop
        start
      end

      task :stop, :roles => :selenium_grid_hub, :on_error => :continue do
        rsudo "cat #{rubber_env.selenium_grid_hub_dir}/hub.pid | xargs kill; exit 0"
      end

      task :start, :roles => :selenium_grid_hub do
        rsudo "#{rubber_env.selenium_grid_hub_dir}/startup.sh"
      end
    end

  end
end
