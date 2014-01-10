require 'httparty'

namespace :rubber do

  namespace :stackdriver do

    rubber.allow_optional_tasks(self)


    before "rubber:install_packages", "rubber:stackdriver:setup_apt_sources"

    task :setup_apt_sources, :roles => :stackdriver_agent do
      rubber.sudo_script 'configure_postgresql_repository', <<-ENDSCRIPT
        if [[ ! -f /etc/apt/sources.list.d/stackdriver.list ]]; then
          curl -o /etc/apt/sources.list.d/stackdriver.list http://repo.stackdriver.com/precise.list
          curl --silent https://www.stackdriver.com/RPM-GPG-KEY-stackdriver | apt-key add -
          echo "stackdriver-agent stackdriver-agent/apikey string #{Rubber.config.stackdriver_api_key}" | debconf-set-selections
        fi
      ENDSCRIPT
    end

    desc "Start stackdriver-agent"
    task :start, :roles => :stackdriver_agent do
      rsudo "service stackdriver-agent  start"
    end

    desc "Stop stackdriver-agent"
    task :stop, :roles => :stackdriver_agent do
      rsudo "service stackdriver-agent  stop || true"
    end

    desc "Restart stackdriver-agent"
    task :restart, :roles => :stackdriver_agent do
      stop
      start
    end

    if Rubber.env == 'production'
      after  "deploy", "rubber:stackdriver:deployment_notification"
      after  "deploy:migrations", "rubber:stackdriver:deployment_notification"
    end

    task :deployment_notification do
      send_deploy_events(deploy_events)
    end

    def deploy_user
      fetch(:stackdriver_deploy_user,
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

    def deploy_events
      events = []

      # Add an event for top level deploy project
      deploy_event = {
        'revision_id' => real_revision[0..7],
        'deployed_by' => deploy_user,
        'deployed_to' => Rubber.env,
        'repository' => repo_name(repository)
      }
      events << deploy_event

      events
    end

    def send_deploy_events(events)
      puts "Sending deployment events to stackdriver"

      headers = {
        'content-type' => 'application/json',
        'x-stackdriver-apikey' => Rubber.config.stackdriver_api_key
      }

      events.each do |event|
        resp = HTTParty.post(
            'https://event-gateway.stackdriver.com/v1/deployevent',
            headers: headers,
            body: event.to_json
        )
        puts 'Failed to submit code deploy event: #{event.inspect}' unless resp.success?
      end
    end

  end

end
