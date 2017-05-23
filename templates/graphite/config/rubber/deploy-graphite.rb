
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

      after "rubber:install_packages", "rubber:graphite:server:install"
      after "rubber:bootstrap", "rubber:graphite:server:bootstrap"

      desc <<-DESC
        Installs graphite server components
      DESC
      task :install, :roles => :graphite_server do
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
        rsudo "#{service_status('carbon-cache')} || #{service_start('carbon-cache')}"
      end

      desc "Stop graphite system monitoring"
      task :stop, :roles => :graphite_server do
        rsudo "#{service_stop('carbon-cache')} || true"
      end

      desc "Restart graphite system monitoring"
      task :restart, :roles => :graphite_server do
        stop
        start
      end

      desc "Display status of graphite system monitoring"
      task :status, :roles => :graphite_server do
        rsudo "#{service_status('carbon-cache')} || true"
        rsudo "ps -eopid,user,cmd | grep [c]arbon || true"
        rsudo "sudo netstat -tupln | grep [p]ython || true"
      end

    end

    namespace :web do

      rubber.allow_optional_tasks(self)

      after "rubber:graphite:server:bootstrap", "rubber:graphite:web:bootstrap"

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

          restart
        end
      end

      desc "Start graphite web server"
      task :start, :roles => :graphite_web do
        rsudo "#{service_status('graphite-web')} || #{service_start('graphite-web')}"
      end

      desc "Stop graphite web server"
      task :stop, :roles => :graphite_web do
        rsudo "#{service_stop('graphite-web')} || true"
      end

      desc "Restart graphite web server"
      task :restart, :roles => :graphite_web do
        stop
        start
      end

      desc "Display status of graphite web server"
      task :status, :roles => :graphite_web do
        rsudo "#{service_status('graphite-web')} || true"
        rsudo "ps -eopid,user,cmd | grep '[g]raphite/conf/uwsgi.ini' || true"
        rsudo "netstat -tupln | grep uwsgi || true"
      end

    end

    def create_storage_directory
      rubber.sudo_script 'create_graphite_storage_directory', <<-ENDSCRIPT
        if [[ ! -e #{rubber_env.graphite_storage_dir} ]]; then
          mkdir -p #{rubber_env.graphite_storage_dir}
          chown -R _graphite:www-data #{rubber_env.graphite_storage_dir}
        fi
      ENDSCRIPT
    end

  end

end
