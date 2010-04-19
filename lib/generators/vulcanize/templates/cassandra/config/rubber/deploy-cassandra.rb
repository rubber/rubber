
namespace :rubber do

  namespace :cassandra do
  
    rubber.allow_optional_tasks(self)
  
    after "rubber:install_packages", "rubber:cassandra:install"
    
    task :install, :roles => :cassandra do
      rubber.sudo_script 'install_cassandra', <<-ENDSCRIPT
        if [[ ! -d "#{rubber_env.cassandra_dir}" ]]; then
          wget -qNP #{cassandra_pkg_url}
          tar -C #{cassandra_prefix} -zxf apache-cassandra-#{cassandra_version}-bin.tar.gz
        fi
      ENDSCRIPT
    end

    task :bootstrap, :roles => :cassandra do
      rubber.sudo_script 'install_cassandra', <<-ENDSCRIPT
        if [[ ! -d "#{rubber_env.cassandra_data_dir}" ]]; then
          # After everything installed on machines, we need the source tree
          # on hosts in order to run rubber:config for bootstrapping the db
          deploy.update_code
          
          # Gen just the conf for cassandra
          rubber.run_config(:RUBBER_ENV => RUBBER_ENV, :FILE => "role/cassandra", :FORCE => true, :deploy_path => release_path)
        fi
      ENDSCRIPT
      rubber.cassandra.start
    end

    before "deploy:stop", "rubber:cassandra:stop"
    after "deploy:start", "rubber:cassandra:start"
    after "deploy:restart", "rubber:cassandra:restart"
    
    task :restart, :roles => :cassandra do
      rubber.cassandra.stop
      rubber.cassandra.start
    end
    
    task :stop, :roles => :cassandra do
      rsudo "kill `cat #{rubber_env.cassandra_pid_file}`"
    end
    
    task :start, :roles => :cassandra do
      rsudo "#{rubber_env.cassandra_dir}/bin/cassandra -p #{cassandra_pid_file}"
    end
    
  end
end
