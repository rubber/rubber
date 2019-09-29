namespace :rubber do
  namespace :statsd do
    rubber.allow_optional_tasks(self)

    before "rubber:install_packages", "rubber:statsd:setup_apt_sources"

    task :setup_apt_sources, :roles => :statsd do
      rubber.sudo_script "configure_statsd_repository", <<-ENDSCRIPT
        add-apt-repository -y ppa:chris-lea/node.js
      ENDSCRIPT
    end

    after "rubber:install_packages", "rubber:statsd:install"

    task :install, :roles => :statsd do
      rubber.sudo_script "custom_statsd_install", <<-ENDSCRIPT
        export STATSD_HOME=#{rubber_env.statsd_dir}

        if [[ ! -d $STATSD_HOME ]]; then
          git clone -b #{rubber_env.statsd_branch} #{rubber_env.statsd_repository} $STATSD_HOME
        fi
      ENDSCRIPT
    end

    after "rubber:bootstrap", "rubber:statsd:bootstrap"

    task :bootstrap, :roles => :statsd do
      rubber.sudo_script "bootstrap_statsd", <<-ENDSCRIPT
        mkdir -p /etc/statsd
      ENDSCRIPT
    end

    desc "Stops the statsd server"
    task :stop, :roles => :statsd, :on_error => :continue do
      rsudo "service statsd stop || true"
    end

    desc "Starts the statsd server"
    task :start, :roles => :statsd do
      rsudo "service statsd start"
    end

    desc "Restarts the statsd server"
    task :restart, :roles => :statsd do
      stop
      start
    end

    after "deploy:restart", "rubber:statsd:reload"

    desc "Reloads the statsd server"
    task :reload, :roles => :statsd do
      restart
    end

  end
end
