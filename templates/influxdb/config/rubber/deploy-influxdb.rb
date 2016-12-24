namespace :rubber do

  namespace :influxdb do

    rubber.allow_optional_tasks(self)

    after "rubber:install_packages", "rubber:influxdb:install"

    task :install, :roles => :influxdb do
      rubber.sudo_script 'install_influxdb', <<-ENDSCRIPT
        if ! dpkg -s influxdb &> /dev/null; then
          wget -qNP /tmp #{rubber_env.influxdb_package_url}
          dpkg -i /tmp/#{File.basename(rubber_env.influxdb_package_url)}
        fi
      ENDSCRIPT
    end

    after "rubber:bootstrap", "rubber:influxdb:bootstrap"

    task :bootstrap, :roles => :influxdb do
      exists = capture("echo $(ls #{rubber_env.influxdb_data_dir} 2> /dev/null)")
      if exists.strip.size == 0
        rubber.update_code_for_bootstrap
        rubber.run_config(:file => "role/influxdb/", :force => true, :deploy_path => release_path)

        restart
      end
    end

    task :start, :roles => :influxdb do
      rsudo "service influxdb start"
    end

    task :stop, :roles => :influxdb do
      rsudo "service influxdb stop || true"
    end

    task :restart, :roles => :influxdb do
      stop
      start
    end

    if Rubber.env == 'production'
      after  "deploy", "rubber:influxdb:deployment_notification"
      after  "deploy:migrations", "rubber:influxdb:deployment_notification"
    end

    task :deployment_notification do
      send_deploy_event
    end

    def deploy_user
      fetch(:influxdb_deploy_user,
        if (u = %x{git config user.name}.strip) != ""
          u
        elsif (u = ENV['USER']) != ""
          u
        else
          "Someone"
        end
      )
    end

    def repo_name(repository)
      repository.split('/').last.gsub(/\..*/, '')
    end

    def deploy_event

      # single deploy event
      event = {
        'environment' => Rubber.env,
        'host_filter' => ENV['FILTER'],
        'role_filter' => ENV['FILTER_ROLES'],
        'user' => deploy_user,
        'repositories' => []
      }

      # Add repo/rev for top level deploy project
      event['repositories'] << {
          'repository' => repo_name(repository),
          'revision' => real_revision[0..7]
      }

      # add repo/rev for each project
      top.namespaces.each do |name, ns|
        if ns.respond_to?(:project_settings)
          rev = ENV['NO_SCM'] ? "noscm_#{Time.now.to_i}" : ns.real_revision[0..7]
          event['repositories'] << {
              'repository' => repo_name(ns.repository),
              'revision' => rev
          }
        end
      end

      event
    end

    def send_deploy_event
      puts "Sending deployment events to influxdb"

      event = deploy_event
      now = (Time.now.to_f * 10**9).to_i
      type = "deploy"

      title = "Deployed"

      details = []
      details << "host filter: #{event['host_filter']}" if event['host_filter']
      details << "role filter: #{event['role_filter']}" if event['role_filter']
      details.concat(event['repositories'].collect {|r| "#{r['repository']}: #{r['revision']}"})
      details = details.join("<br/>")

      deploy_tags = "#{event['environment']},#{event['user']}"

      data = "events type=#{type.to_json},title=#{title.to_json},details=#{details.to_json},deploy_tags=#{deploy_tags.to_json} #{now}"
      url = "http://#{rubber_instances.for_role('influxdb').first.full_name}:#{rubber_env.influxdb_http_port}/write?db=collectd"

      run "curl -XPOST '#{url}' --data-binary '#{data}'", :once => true
    end

  end
end
