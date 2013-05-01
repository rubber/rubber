
namespace :rubber do
  
  namespace :collectd do
  
    rubber.allow_optional_tasks(self)

    after "rubber:bootstrap", "rubber:collectd:bootstrap"
    after "deploy:restart", "rubber:collectd:restart_rubber_plugin"


    task :bootstrap, :roles => :collectd do
      exists = capture("echo $(grep Rubber /etc/collectd/collectd.conf 2> /dev/null)")
      if exists.strip.size == 0
        rubber.update_code_for_bootstrap

        rubber.run_config(:file => "role/collectd/", :force => true, :deploy_path => release_path)

        restart
      end
    end

    desc "Start collectd system monitoring"
    task :start, :roles => :collectd do
      rsudo "service collectd status || service collectd start"
    end
    
    desc "Stop collectd system monitoring"
    task :stop, :roles => :collectd do
      rsudo "service collectd stop || true"
    end
    
    desc "Restart collectd system monitoring"
    task :restart, :roles => :collectd do
      stop
      start
    end

    desc "Restart collectd rubber plugin"
    task :restart_rubber_plugin, :roles => :collectd do
      # Need to kill rubber collectd runner script to force collectd to restart
      # it after deploy so that the runner script gets the new paths
      rsudo "pkill -fn #{rubber_env.rubber_collectd_runner.sub(/./, '[\0]')} ; exit 0"
    end

    desc "Display status of collectd system monitoring"
    task :status, :roles => :collectd do
      rsudo "service collectd status || true"
      rsudo "ps -eopid,user,fname | grep [c]ollectd || true"
    end

  end

end
