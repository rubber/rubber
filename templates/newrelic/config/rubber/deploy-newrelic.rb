
namespace :rubber do

  namespace :newrelic do

    rubber.allow_optional_tasks(self)

    before "rubber:install_packages", "rubber:newrelic:install_newrelic_apt"

    task :install_newrelic_apt, :roles => :newrelic do
      rubber.sudo_script 'install_newrelic', <<-ENDSCRIPT
        if [[ -z $(cat /etc/apt/sources.list.d/newrelic.list 2> /dev/null) ]]; then
          wget -O /etc/apt/sources.list.d/newrelic.list http://download.newrelic.com/debian/newrelic.list
          apt-key adv --keyserver hkp://subkeys.pgp.net --recv-keys 548C16BF
        fi
      ENDSCRIPT
    end

    after "rubber:bootstrap", "rubber:newrelic:bootstrap"

    task :bootstrap, :roles => :newrelic do
      rubber.sudo_script 'bootstrap_newrelic', <<-ENDSCRIPT
        if [[ -z $(cat /etc/newrelic/nrsysmond.cfg | grep #{rubber_env.nrsysmond_license_key} 2> /dev/null) ]]; then
          nrsysmond-config --set license_key=#{rubber_env.nrsysmond_license_key}
        fi
      ENDSCRIPT

      restart
    end

    desc "Start newrelic system monitoring"
    task :start, :roles => :newrelic do
      rsudo "service newrelic-sysmond start"
    end

    desc "Stop newrelic system monitoring"
    task :stop, :roles => :newrelic do
      rsudo "service newrelic-sysmond stop || true"
    end

    desc "Restart newrelic system monitoring"
    task :restart, :roles => :newrelic do
      stop
      start
    end

  end

end
