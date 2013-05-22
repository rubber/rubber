
namespace :rubber do

  namespace :newrelic do

    rubber.allow_optional_tasks(self)

    before "rubber:install_packages", "rubber:newrelic:install_newrelic_apt"

    task :install_newrelic_apt, :roles => :newrelic do
      rubber.sudo_script 'install_newrelic', <<-ENDSCRIPT
        wget -O /etc/apt/sources.list.d/newrelic.list http://download.newrelic.com/debian/newrelic.list
        apt-key adv --keyserver hkp://subkeys.pgp.net --recv-keys 548C16BF
      ENDSCRIPT
    end

    after "rubber:bootstrap", "rubber:graphite:server:bootstrap"

    task :bootstrap, :roles => :newrelic do
      exists = capture("echo $(cat /etc/newrelic/nrsysmond.cfg | grep #{rubber_env.nrsysmond_license_key} 2> /dev/null)")
      if exists.strip.size == 0
        
        rubber.sudo_script 'bootstrap_newrelic', <<-ENDSCRIPT
          nrsysmond-config --set license_key=#{rubber_env.nrsysmond_license_key}
        ENDSCRIPT
  
        # After everything installed on machines, we need the source tree
        # on hosts in order to run rubber:config for bootstrapping the db
        rubber.update_code_for_bootstrap
  
        restart
      end
    end

    desc "Start graphite system monitoring"
    task :start, :roles => :newrelic do
      rsudo "service newrelic-sysmond start"
    end

    desc "Stop graphite system monitoring"
    task :stop, :roles => :newrelic do
      rsudo "service newrelic-sysmond stop || true"
    end

    desc "Restart graphite system monitoring"
    task :restart, :roles => :newrelic do
      stop
      start
    end

  end

end
