
namespace :rubber do

  namespace :cassandra do
  
    rubber.allow_optional_tasks(self)
  
    after "rubber:install_packages", "rubber:cassandra:install"
    
    task :install, :roles => :cassandra do
      rubber.sudo_script 'install_cassandra', <<-ENDSCRIPT
        if [[ ! -d "#{rubber_env.cassandra_dir}" ]]; then
          wget -qNP /tmp #{rubber_env.cassandra_pkg_url}
          tar -C #{rubber_env.cassandra_prefix} -zxf /tmp/apache-cassandra-#{rubber_env.cassandra_version}-bin.tar.gz
          wget -qNO #{rubber_env.cassandra_dir}/jmxterm.jar http://downloads.sourceforge.net/project/cyclops-group/jmxterm/1.0-alpha-4/jmxterm-1.0-alpha-4-uber.jar
        fi
      ENDSCRIPT
    end

    after "rubber:bootstrap", "rubber:cassandra:bootstrap"

    task :bootstrap, :roles => :cassandra do
      instances = rubber_instances.for_role("cassandra") & rubber_instances.filtered
      instances.each do |ic|
        task_name = "_bootstrap_cassandra_#{ic.full_name}".to_sym()
        task task_name, :hosts => ic.full_name do
          env = rubber_cfg.environment.bind("cassandra", ic.name)
          exists = capture("echo $(ls #{env.cassandra_data_dir}/ 2> /dev/null)")
          if exists.strip.size == 0
            # After everything installed on machines, we need the source tree
            # on hosts in order to run rubber:config for bootstrapping the db
            deploy.update_code

            # Gen just the conf for cassandra
            rubber.run_config(:RUBBER_ENV => RUBBER_ENV, :FILE => "role/cassandra", :FORCE => true, :deploy_path => release_path)

            cassandra_start
            
            # temporary hack to load initial schema from cassandra.yaml until
            # something better available.  Subsequent schema changes should be
            # done using thrift system_* api
            # http://wiki.apache.org/cassandra/FAQ#no_keyspaces
            # http://wiki.apache.org/cassandra/LiveSchemaUpdates
            if instances.size == 1
              rubber.sudo_script "install_cassandra_schema", <<-ENDSCRIPT
                echo run -b org.apache.cassandra.service:type=StorageService loadSchemaFromYAML |\
                  java -jar #{rubber_env.cassandra_dir}/jmxterm.jar -n -l #{ic.full_name}:#{rubber_env.cassandra_jmx_port}
              ENDSCRIPT
            end
          end
        end
        send task_name
      end
    end
    
    on :load do
      rubber.serial_task self, :serial_restart, :roles => :cassandra do
        cassandra_stop
        cassandra_start
      end

      rubber.serial_task self, :serial_reload, :roles => :cassandra do
      end
    end

    def cassandra_stop
      rsudo "pid=`cat #{rubber_env.cassandra_pid_file}` && kill $pid; while ps $pid &> /dev/null; do sleep 1; done"
    end

    def cassandra_start
      rsudo "nohup #{rubber_env.cassandra_dir}/bin/cassandra -p #{rubber_env.cassandra_pid_file} &> #{rubber_env.cassandra_log_dir}/startup.log"
    end

    task :restart, :roles => :cassandra do
      rubber.cassandra.stop
      rubber.cassandra.start
    end
    
    task :stop, :roles => :cassandra do
      cassandra_stop
    end
    
    task :start, :roles => :cassandra do
      cassandra_start
    end
    
  end
end
