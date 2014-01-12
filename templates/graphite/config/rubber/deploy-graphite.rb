
namespace :rubber do

  namespace :graphite do

    rubber.allow_optional_tasks(self)

    after "rubber:install_packages", "rubber:graphite:install_collectd_graphite_plugin"

    task :install_collectd_graphite_plugin, :roles => :collectd do
      rubber.sudo_script 'install_collectd', <<-ENDSCRIPT
        if [[ ! -f "/usr/local/share/perl/5.10.1/Collectd/Plugins/Graphite.pm" ]]; then
          wget --no-check-certificate -qNO /tmp/joemiller-collectd-graphite.tar.gz https://github.com/joemiller/collectd-graphite/tarball/#{rubber_env.collectd_graphite_plugin_version}
          tar -C /tmp -zxf /tmp/joemiller-collectd-graphite.tar.gz
          cd /tmp/joemiller-collectd-graphite-*
          perl Makefile.PL
          make
          make test
          make install
        fi
      ENDSCRIPT
    end

    task :install_graphite_from_repo, :roles => [:graphite_server, :graphite_web] do
      rubber.sudo_script 'install_graphite_from_repo', <<-ENDSCRIPT
        if [[ ! -d "/opt/graphite" ]]; then
          mkdir -p /tmp/graphite_install
          cd /tmp/graphite_install
          bzr branch lp:graphite -r #{rubber_env.graphite_repo_version}

          pushd graphite/whisper
          python setup.py install
          popd

          pushd graphite/carbon
          python setup.py install
          popd

          pushd graphite
          python setup.py install
          popd
        fi
      ENDSCRIPT
    end

    desc <<-DESC
      Cleans out old whisper storage files for non-existant instances so they don't show in webui
    DESC
    task :clean_storage, :roles => [:graphite_server] do
      active_instances = rubber_instances.collect {|ic| ic.name }.sort
      stored_instances = capture("ls /opt/graphite/storage/whisper/servers/").split.sort
      cleaning_instances = stored_instances - active_instances

      if cleaning_instances.size > 0
        logger.info "Cleaning dead instances from graphite storage: #{cleaning_instances.join(',')}"

        do_clean = true
        if (cleaning_instances.size.to_f / stored_instances.size) > 0.01
          value = Capistrano::CLI.ui.ask("Graphite storage files to be cleaned exceeds threshold, proceed? [y/N]?: ")
          do_clean = (value =~ /^y/)
        end

        if do_clean
          rsudo "rm -rf /opt/graphite/storage/whisper/servers/{#{cleaning_instances.join(',')}}"
        end

      end
    end

    namespace :server do

      rubber.allow_optional_tasks(self)

      if Rubber::Configuration.rubber_env.graphite_repo_version
        after "rubber:install_packages", "rubber:graphite:install_graphite_from_repo"
      else
        after "rubber:install_packages", "rubber:graphite:server:install"
      end

      after "rubber:bootstrap", "rubber:graphite:server:bootstrap"

      desc <<-DESC
        Installs graphite server components
      DESC
      task :install, :roles => :graphite_server do
        rubber.sudo_script 'install_graphite_server', <<-ENDSCRIPT
          if [[ ! -f "/opt/graphite/bin/carbon-cache.py" ]]; then
            wget -qNP /tmp #{rubber_env.graphite_whisper_package_url}
            tar -C /tmp -zxf /tmp/#{rubber_env.graphite_whisper_package_url.gsub(/.*\//, '')}
            cd /tmp/#{rubber_env.graphite_whisper_package_url.gsub(/.*\//, '').gsub('.tar.gz', '')}
            python setup.py install

            wget -qNP /tmp #{rubber_env.graphite_carbon_package_url}
            tar -C /tmp -zxf /tmp/#{rubber_env.graphite_carbon_package_url.gsub(/.*\//, '')}
            cd /tmp/#{rubber_env.graphite_carbon_package_url.gsub(/.*\//, '').gsub('.tar.gz', '')}
            python setup.py install

            rm -rf /opt/graphite/storage
            mkdir #{rubber_env.graphite_storage_dir}
            chown www-data:www-data #{rubber_env.graphite_storage_dir}
            ln -s #{rubber_env.graphite_storage_dir} /opt/graphite/storage
          fi
        ENDSCRIPT
      end

      task :bootstrap, :roles => :graphite_server do
        exists = capture("echo $(ls /opt/graphite/storage/whisper/ 2> /dev/null)")
        if exists.strip.size == 0
          rubber.update_code_for_bootstrap

          rubber.run_config(:file => "role/graphite_server/", :force => true, :deploy_path => release_path)

          restart
        end
      end

      desc "Start graphite system monitoring"
      task :start, :roles => :graphite_server do
        rsudo "service graphite-server start"
      end

      desc "Stop graphite system monitoring"
      task :stop, :roles => :graphite_server do
        rsudo "service graphite-server stop || true"
      end

      desc "Restart graphite system monitoring"
      task :restart, :roles => :graphite_server do
        stop
        start
      end

      desc "Display status of graphite system monitoring"
      task :status, :roles => :graphite_server do
        rsudo "service graphite-server status || true"
        rsudo "ps -eopid,user,cmd | grep [c]arbon || true"
        rsudo "sudo netstat -tupln | grep [p]ython || true"
      end

    end

    namespace :web do

      rubber.allow_optional_tasks(self)

      if Rubber::Configuration.rubber_env.graphite_repo_version
        after "rubber:graphite:server:install", "rubber:graphite:install_graphite_from_repo"
      else
        after "rubber:graphite:server:install", "rubber:graphite:web:install"
      end

      after "rubber:graphite:server:bootstrap", "rubber:graphite:web:bootstrap"

      desc <<-DESC
        Installs graphite web components
      DESC
      task :install, :roles => :graphite_web do
        rubber.sudo_script 'install_graphite_web', <<-ENDSCRIPT
          if [[ ! -d "/opt/graphite/webapp" ]]; then
            wget -qNP /tmp #{rubber_env.graphite_web_package_url}
            tar -C /tmp -zxf /tmp/#{rubber_env.graphite_web_package_url.gsub(/.*\//, '')}
            cd /tmp/#{rubber_env.graphite_web_package_url.gsub(/.*\//, '').gsub('.tar.gz', '')}
            # python check-dependencies.py
            python setup.py install
          fi
        ENDSCRIPT
      end

      task :bootstrap, :roles => :graphite_web do
        exists = capture("echo $(ls /opt/graphite/storage/graphite.db 2> /dev/null)")
        if exists.strip.size == 0
          rubber.update_code_for_bootstrap

          rubber.run_config(:file => "role/graphite_web/", :force => true, :deploy_path => release_path)

          # django email validation barfs on localhost, but for full_host to work
          # in admin_email, we need a env with host defined
          web_instance = rubber_instances.for_role("graphite_web").first
          env = rubber_cfg.environment.bind("graphite_web", web_instance.name)
          email = env.admin_email

          rubber.sudo_script 'bootstrap_graphite_web', <<-ENDSCRIPT
            cd /opt/graphite/webapp/graphite
            python manage.py syncdb --noinput
            python manage.py createsuperuser --username admin --email #{email} --noinput
            python manage.py shell <<EOF
from django.contrib.auth.models import User
u = User.objects.get(username__exact='admin')
u.set_password('admin1')
u.save()
EOF
            mkdir -p /opt/graphite/storage/log/webapp/
            chown -R www-data:www-data /opt/graphite/storage/
          ENDSCRIPT

          restart
        end
      end

      desc "Start graphite web server"
      task :start, :roles => :graphite_web do
        rsudo "service graphite-web start"
      end

      desc "Stop graphite web server"
      task :stop, :roles => :graphite_web do
        rsudo "service graphite-web stop || true"
      end

      desc "Restart graphite web server"
      task :restart, :roles => :graphite_web do
        stop
        start
      end

      desc "Display status of graphite web server"
      task :status, :roles => :graphite_web do
        rsudo "service graphite-web status || true"
        rsudo "ps -eopid,user,cmd | grep '[g]raphite/conf/uwsgi.ini' || true"
        rsudo "netstat -tupln | grep uwsgi || true"
      end

    end

  end

end
