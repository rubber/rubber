
namespace :rubber do
  
  namespace :munin do
  
    rubber.allow_optional_tasks(self)

    after "rubber:install_packages", "rubber:munin:custom_install"

    # sometimes apt-get install of munin doesn't end up configuring
    # plugins (e.g. installing postfix at same time, postfix plugin
    # configure barfs as postfix not configured yet)
    desc <<-DESC
      Reconfigures munin
    DESC
    task :custom_install do
      rubber.sudo_script 'setup_munin_plugins', <<-ENDSCRIPT
        munin-node-configure --shell --remove-also > /tmp/setup-munin-plugins 2> /dev/null || true
        sh /tmp/setup-munin-plugins
      ENDSCRIPT
      restart
    end

    # after "deploy:stop", "rubber:munin:stop"
    # before "deploy:start", "rubber:munin:start"
    # after "deploy:restart", "rubber:munin:restart"

    desc "Start munin system monitoring"
    task :start do
      rsudo "service munin-node start"
    end
    
    desc "Stop munin system monitoring"
    task :stop do
      rsudo "service munin-node stop; exit 0"
    end
    
    desc "Restart munin system monitoring"
    task :restart do
      stop
      start
    end
  
  end

end
