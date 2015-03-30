
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
      if old_ubuntu?
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
    end

    desc <<-DESC
      Cleans out old whisper storage files for non-existent instances so they don't show in webui
    DESC
    task :clean_storage, :roles => [:graphite_server] do
      active_instances = rubber_instances.collect {|ic| ic.name }.sort
      stored_instances = capture("ls #{rubber_env.graphite_storage_dir}/whisper/servers/").split.sort
      cleaning_instances = stored_instances - active_instances

      if cleaning_instances.size > 0
        logger.info "Cleaning dead instances from graphite storage: #{cleaning_instances.join(',')}"

        do_clean = true
        if (cleaning_instances.size.to_f / stored_instances.size) > 0.01
          value = Capistrano::CLI.ui.ask("Graphite storage files to be cleaned exceeds threshold, proceed? [y/N]?: ")
          do_clean = (value =~ /^y/)
        end

        if do_clean
          rsudo "rm -rf #{rubber_env.graphite_storage_dir}/whisper/servers/{#{cleaning_instances.join(',')}}"
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
        if old_ubuntu?
          rubber.sudo_script 'install_graphite_server', <<-ENDSCRIPT
            if [[ ! -f "/opt/graphite/bin/carbon-cache.py" ]]; then
              wget --content-disposition -qNP /tmp #{rubber_env.graphite_whisper_package_url}
              tar -C /tmp -zxf /tmp/whisper-#{rubber_env.graphite_version}.tar.gz
              cd /tmp/whisper-#{rubber_env.graphite_version}
              python setup.py install
              cd /tmp
              rm -rf whisper-#{rubber_env.graphite_version}
              rm whisper-#{rubber_env.graphite_version}.tar.gz

              wget --content-disposition -qNP /tmp #{rubber_env.graphite_carbon_package_url}
              tar -C /tmp -zxf /tmp/carbon-#{rubber_env.graphite_version}.tar.gz
              cd /tmp/carbon-#{rubber_env.graphite_version}
              python setup.py install
              cd /tmp
              rm -r carbon-#{rubber_env.graphite_version}
              rm carbon-#{rubber_env.graphite_version}.tar.gz

              rm -rf #{rubber_env.graphite_storage_dir}
              mkdir #{rubber_env.graphite_storage_dir}
              chown www-data:www-data #{rubber_env.graphite_storage_dir}
              ln -s #{rubber_env.graphite_storage_dir} /opt/graphite/storage
            fi
          ENDSCRIPT
        end

        create_storage_directory
      end

      task :bootstrap, :roles => :graphite_server do
        exists = capture("echo $(ls #{rubber_env.graphite_storage_dir}/whisper/ 2> /dev/null)")
        if exists.strip.size == 0
          rubber.update_code_for_bootstrap

          rubber.run_config(:file => "role/graphite_server/", :force => true, :deploy_path => release_path)

          restart
        end
      end

      desc "Start graphite system monitoring"
      task :start, :roles => :graphite_server do
        if old_ubuntu?
          rsudo 'service graphite-server start'
        else
          rsudo 'service carbon-cache start'
        end
      end

      desc "Stop graphite system monitoring"
      task :stop, :roles => :graphite_server do
        if old_ubuntu?
          rsudo 'service graphite-server stop || true'
        else
          rsudo 'service carbon-cache stop || true'
        end
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
        if old_ubuntu?
          rubber.sudo_script 'install_graphite_web', <<-ENDSCRIPT
            if [[ ! -d "/opt/graphite/webapp" ]]; then
              wget --content-disposition -qNP /tmp #{rubber_env.graphite_web_package_url}
              tar -C /tmp -zxf /tmp/graphite-web-#{rubber_env.graphite_version}.tar.gz
              cd /tmp/graphite-web-#{rubber_env.graphite_version}

              # python check-dependencies.py
              python setup.py install

              cd /tmp
              rm -r graphite-web-#{rubber_env.graphite_version}
              rm graphite-web-#{rubber_env.graphite_version}.tar.gz
            fi
          ENDSCRIPT
        end
      end

      task :bootstrap, :roles => :graphite_web do
        exists = capture("echo $(ls #{rubber_env.graphite_storage_dir}/graphite.db 2> /dev/null)")
        if exists.strip.size == 0
          rubber.update_code_for_bootstrap

          rubber.run_config(:file => "role/graphite_web/", :force => true, :deploy_path => release_path)

          # django email validation barfs on localhost, but for full_host to work
          # in admin_email, we need a env with host defined
          web_instance = rubber_instances.for_role("graphite_web").first
          env = rubber_cfg.environment.bind("graphite_web", web_instance.name)
          email = env.admin_email

          create_storage_directory

          if old_ubuntu?
            rubber.sudo_script 'bootstrap_graphite_web', <<-ENDSCRIPT
              mkdir -p #{rubber_env.graphite_storage_dir}/log/webapp/
              chown -R www-data:www-data #{rubber_env.graphite_storage_dir}/log/

              cd /opt/graphite/webapp/graphite
              python manage.py syncdb --noinput
              python manage.py createsuperuser --username admin --email #{email} --noinput
              python manage.py shell <<EOF
from django.contrib.auth.models import User
u = User.objects.get(username__exact='admin')
u.set_password('admin1')
u.save()
EOF
            ENDSCRIPT
          else
            rubber.sudo_script 'bootstrap_graphite_web', <<-ENDSCRIPT
              # Ubuntu 14.04 ships with a broken graphite-web package.  It renames the build-index.sh file to be a binary
              # on the PATH, but it fails to update any of the code that references the original file location, causing
              # graphite-web to fail on initial load.  We fix that here by setting up a symlink to the renamed binary.

              mkdir -p /usr/share/graphite-web/bin/
              ln -s /usr/bin/graphite-build-search-index /usr/share/graphite-web/bin/build-index.sh

              graphite-manage syncdb --noinput
              graphite-manage createsuperuser --username admin --email #{email} --noinput
              graphite-manage shell <<EOF
from django.contrib.auth.models import User
u = User.objects.get(username__exact='admin')
u.set_password('admin1')
u.save()
EOF
            ENDSCRIPT
          end

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

    def create_storage_directory
      owner = old_ubuntu? ? 'www-data' : '_graphite'

      rubber.sudo_script 'create_graphite_storage_directory', <<-ENDSCRIPT
        if [[ ! -e #{rubber_env.graphite_storage_dir} ]]; then
          mkdir -p #{rubber_env.graphite_storage_dir}
          chown -R #{owner}:www-data #{rubber_env.graphite_storage_dir}
        fi
      ENDSCRIPT
    end

    def old_ubuntu?
      is_old_ubuntu = rubber_instance.os_version == '12.04'
    end

  end

end
