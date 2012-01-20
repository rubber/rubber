
namespace :rubber do
  
  namespace :munin do
  
    rubber.allow_optional_tasks(self)

    after "rubber:install_packages", "rubber:munin:install"

    # sometimes apt-get install of munin doesn't end up configuring
    # plugins (e.g. installing postfix at same time, postfix plugin
    # configure barfs as postfix not configured yet)
    desc <<-DESC
      Reconfigures munin
    DESC
    task :install, :roles => [:munin] do
      rubber.sudo_script 'setup_munin_plugins', <<-ENDSCRIPT
        munin-node-configure --shell --remove-also > /tmp/setup-munin-plugins 2> /dev/null || true
        sh /tmp/setup-munin-plugins
      ENDSCRIPT
      restart
    end

    before "rubber:munin:install", "rubber:munin:install_mysql_plugin"

    desc <<-DESC
      Installs some extra munin graphs
    DESC
    task :install_mysql_plugin, :roles => [:mysql_master, :mysql_slave] do
      rubber.sudo_script 'install_munin_mysql', <<-ENDSCRIPT
        if [ ! -f /usr/share/munin/plugins/mysql_ ]; then
          wget --no-check-certificate -qN -O /usr/share/munin/plugins/mysql_ https://github.com/kjellm/munin-mysql/raw/master/mysql_
          wget --no-check-certificate -qN -O /etc/munin/plugin-conf.d/mysql_.conf https://github.com/kjellm/munin-mysql/raw/master/mysql_.conf
        fi
      ENDSCRIPT
    end

    after "rubber:munin:install", "rubber:munin:install_postgresql_plugin"
    
    task :install_postgresql_plugin, :roles => [:postgresql_master, :postgresql_slave] do
      regular_plugins = %w[bgwriter checkpoints connections_db users xlog]
      parameterized_plugins = %w[cache connections locks querylength scans transactions tuples]

      commands = ['rm -f /etc/munin/plugins/postgres_*']

      regular_plugins.each do |name|
        commands << "ln -s /usr/share/munin/plugins/postgres_#{name} /etc/munin/plugins/postgres_#{name}"
      end

      parameterized_plugins.each do |name|
        commands << "ln -s /usr/share/munin/plugins/postgres_#{name}_ /etc/munin/plugins/postgres_#{name}_#{rubber_env.db_name}"
      end

      rubber.sudo_script "install_postgresql_munin_plugins", <<-ENDSCRIPT
        #{commands.join(';')}
      ENDSCRIPT
    end
  
    # after "deploy:stop", "rubber:munin:stop"
    # before "deploy:start", "rubber:munin:start"
    # after "deploy:restart", "rubber:munin:restart"

    desc "Start munin system monitoring"
    task :start, :roles => :munin do
      rsudo "service munin-node start"
    end
    
    desc "Stop munin system monitoring"
    task :stop, :roles => :munin do
      rsudo "service munin-node stop; exit 0"
    end
    
    desc "Restart munin system monitoring"
    task :restart, :roles => :munin do
      stop
      start
    end
  
  end

end
