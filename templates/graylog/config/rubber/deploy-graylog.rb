namespace :rubber do

  namespace :graylog do

    rubber.allow_optional_tasks(self)

    before "rubber:install_packages", "rubber:graylog:setup_apt_sources"

    task :setup_apt_sources, :roles => :graylog do
      # Setup apt sources to graylog
      sources = <<-SOURCES
        deb https://packages.graylog2.org/repo/debian/ stable 2.2
      SOURCES
      sources.gsub!(/^[ \t]*/, '')
      put(sources, "/etc/apt/sources.list.d/graylog.list")
      rsudo "apt-key adv --keyserver keyserver.ubuntu.com --recv B1606F22"
    end

    after "rubber:install_packages", "rubber:graylog:enable_service_at_boot"

    task :enable_service_at_boot, :roles => :graylog do
      use_systemd = rubber_instance.os_version.split('.').first.to_i >= 16

      if use_systemd
        rsudo "systemctl enable graylog-server"
      else
        rsudo "rm -f /etc/init/graylog-server.override"
      end
    end

    after "rubber:mongodb:bootstrap", "rubber:graylog:multi_dependency_bootstrap"
    after "rubber:elasticsearch:bootstrap", "rubber:graylog:multi_dependency_bootstrap"
    dependency_count = 0
    task :multi_dependency_bootstrap do
      dependency_count += 1
      if dependency_count == 2
        bootstrap
      end
    end

    before "rubber:graylog:bootstrap", "rubber:mongodb:restart"

    task :bootstrap, :roles => :graylog do
      exists = capture("grep '#{rubber_env.graylog_elasticsearch_index}' /etc/graylog/server/server.conf 2> /dev/null || true")
      if exists.strip.size == 0
        rubber.update_code_for_bootstrap
        rubber.run_config(:file => "role/graylog/", :force => true, :deploy_path => release_path)

        rubber.graylog.server.restart
        sleep 60 # Give graylog-server a bit of time to start up.
      end
    end

    namespace :server do

      rubber.allow_optional_tasks(self)

      after "rubber:graylog:bootstrap", "rubber:graylog:server:create_inputs"

      task :create_inputs, :roles => :graylog_web do
        rubber.sudo_script 'create_inputs', <<-ENDSCRIPT
          # Only create inputs if the system has 0 inputs.  It's a bit of a rough hack, but graylog currently (v0.20.2)
          # doesn't prevent the creation of duplicate conflicting inputs.
          if ! curl -s --user #{rubber_env.graylog_web_username}:#{rubber_env.graylog_web_password} -XGET http://#{rubber_instance.internal_ip}:#{rubber_env.graylog_web_port}/api/system/inputs | grep "GELFUDPInput" &> /dev/null; then
            curl --user #{rubber_env.graylog_web_username}:#{rubber_env.graylog_web_password} -XPOST http://#{rubber_instance.internal_ip}:#{rubber_env.graylog_web_port}/api/system/inputs -H "Content-Type: application/json" -d '{"type": "org.graylog2.inputs.gelf.udp.GELFUDPInput", "title": "gelf-udp", "global": true, "configuration": { "port": #{rubber_env.graylog_server_port}, "bind_address": "0.0.0.0" } }'
          fi

          if ! curl -s --user #{rubber_env.graylog_web_username}:#{rubber_env.graylog_web_password} -XGET http://#{rubber_instance.internal_ip}:#{rubber_env.graylog_web_port}/api/system/inputs | grep "SyslogUDPInput" &> /dev/null; then
            curl --user #{rubber_env.graylog_web_username}:#{rubber_env.graylog_web_password} -XPOST http://#{rubber_instance.internal_ip}:#{rubber_env.graylog_web_port}/api/system/inputs -H "Content-Type: application/json" -d '{"type": "org.graylog2.inputs.syslog.udp.SyslogUDPInput", "title": "syslog-udp", "global": true, "configuration": { "port": #{rubber_env.graylog_syslog_port}, "bind_address": "0.0.0.0" } }'
          fi
        ENDSCRIPT
      end

      desc "Stops the graylog server"
      task :stop, :roles => :graylog_server, :on_error => :continue do
        rsudo "#{service_stop('graylog-server')} || true"
      end

      desc "Starts the graylog server"
      task :start, :roles => :graylog_server do
        rsudo "#{service_start('graylog-server')} || true"
      end

      desc "Restarts the graylog server"
      task :restart, :roles => :graylog_server do
        stop
        start
      end

    end

    namespace :web do

      rubber.allow_optional_tasks(self)

      desc "Stops the graylog web"
      task :stop, :roles => :graylog_web, :on_error => :continue do
        rsudo "#{service_stop('graylog-server')} || true"
      end

      desc "Starts the graylog web"
      task :start, :roles => :graylog_web do
        rsudo "#{service_start('graylog-server')} || true"
      end

      desc "Restarts the graylog web"
      task :restart, :roles => :graylog_web do
        stop
        start
      end

    end

  end

end
