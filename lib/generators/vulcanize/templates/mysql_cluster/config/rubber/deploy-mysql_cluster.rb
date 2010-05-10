
namespace :rubber do
  
  namespace :mysql_cluster do
    
    rubber.allow_optional_tasks(self)
  
    after "rubber:create", "rubber:mysql_cluster:set_db_role"
      
    # Capistrano needs db:primary role for migrate to work
    task :set_db_role do
      sql_instances = rubber_instances.for_role("mysql_sql")
      sql_instances.each do |instance|
        if ! instance.role_names.find {|n| n == 'db'}
          role = Rubber::Configuration::RoleItem.new('db')
          primary_exists = rubber_instances.for_role("db", "primary" => true).size > 0
          role.options["primary"] = true  unless primary_exists
          instance.roles << role
        end
      end
      rubber_instances.save()
      load_roles() unless rubber_env.disable_auto_roles
    end
    
    before "rubber:install_packages", "rubber:mysql_cluster:install"
  
    task :install, :roles => [:mysql_mgm, :mysql_data, :mysql_sql] do
      # Setup apt sources to get a newer version of mysql cluster
      # https://launchpad.net/~mysql-cge-testing/+archive
      #
      
      sources = <<-SOURCES
         # for mysql cluster 6.2
         # deb http://ppa.launchpad.net/mysql-cge-testing/ubuntu hardy main
         # deb-src http://ppa.launchpad.net/mysql-cge-testing/ubuntu hardy main
         
         # for mysql cluster 6.3
         deb http://ppa.launchpad.net/ndb-bindings/ubuntu hardy main
         deb-src http://ppa.launchpad.net/ndb-bindings/ubuntu hardy main
      SOURCES
      sources.gsub!(/^ */, '')
      put(sources, "/etc/apt/sources.list.d/mysql_cluster.list")
    end
      
    after "rubber:bootstrap", "rubber:mysql_cluster:bootstrap"
  
    task :bootstrap, :roles => [:mysql_mgm, :mysql_data, :mysql_sql] do
      # mysql package install starts mysql, so stop it
      rsudo "service mysql stop" rescue nil
      
      # After everything installed on machines, we need the source tree
      # on hosts in order to run rubber:config for bootstrapping the db
      rubber.update_code_for_bootstrap
  
      # Conditionaly bootstrap for each node/role only if that node has not
      # been boostrapped for that role before
      
      rubber_instances.for_role("mysql_mgm").each do |ic|
        task_name = "_bootstrap_mysql_mgm_#{ic.full_name}".to_sym()
        task task_name, :hosts => ic.full_name do
          exists = capture("if grep -c rubber.*mysql_mgm /etc/mysql/ndb_mgmd.cnf &> /dev/null; then echo exists; fi")
          if exists.strip.size == 0
            rubber.run_config(:RUBBER_ENV => RUBBER_ENV, :FILE => "role/mysql_mgm", :deploy_path => release_path)
            rsudo "service mysql-ndb-mgm start"
          end
        end
        send task_name
      end
    
      rubber_instances.for_role("mysql_data").each do |ic|
        task_name = "_bootstrap_mysql_data_#{ic.full_name}".to_sym()
        task task_name, :hosts => ic.full_name do
          exists = capture("if grep -c rubber.*mysql_data /etc/mysql/my.cnf &> /dev/null; then echo exists; fi")
          if exists.strip.size == 0
            rubber.run_config(:RUBBER_ENV => RUBBER_ENV, :FILE => "role/mysql_data", :deploy_path => release_path)
            rsudo "service mysql-ndb start-initial"
          end
        end
        send task_name
      end
      
      rubber_instances.for_role("mysql_sql").each do |ic|
        task_name = "_bootstrap_mysql_sql_#{ic.full_name}".to_sym()
        task task_name, :hosts => ic.full_name do
          exists = capture("if grep -c rubber.*mysql_sql /etc/mysql/my.cnf &> /dev/null; then echo exists; fi")
          if exists.strip.size == 0
            rubber.run_config(:RUBBER_ENV => RUBBER_ENV, :FILE => "role/mysql_sql", :deploy_path => release_path)
            rsudo "service mysql start"
            env = rubber_cfg.environment.bind()
            # For mysql 5.0 cluster, need to create users and database for EVERY sql node
            pass = "identified by '#{env.db_pass}'" if env.db_pass
            rubber.sudo_script "create_mysql_sql_db", <<-ENDSCRIPT
              mysql -u root -e "create database #{env.db_name};"
              mysql -u root -e "grant all on *.* to '#{env.db_user}'@'%' #{pass};"
              mysql -u root -e "grant select on *.* to '#{env.db_slave_user}'@'%' #{pass};"
              mysql -u root -e "grant replication slave on *.* to '#{env.db_replicator_user}'@'%' #{pass};"
              mysql -u root -e "flush privileges;"
            ENDSCRIPT
            
          end
        end
        send task_name
      end
      
    end
  
    desc <<-DESC
      Starts the mysql cluster management daemon on the management node
    DESC
    task :start_mgm, :roles => :mysql_mgm do
      rsudo "service mysql-ndb-mgm start"
    end
    
    desc <<-DESC
      Starts the mysql cluster storage daemon on the data nodes
    DESC
    task :start_data, :roles => :mysql_data do
      rsudo "service mysql-ndb start"
    end
    
    desc <<-DESC
      Starts the mysql cluster sql daemon on the sql nodes
    DESC
    task :start_sql, :roles => :mysql_sql do
      rsudo "service mysql start"
    end
    
    desc <<-DESC
      Stops the mysql cluster management daemon on the management node
    DESC
    task :stop_mgm, :roles => :mysql_mgm do
      rsudo "service mysql-ndb-mgm stop"
    end
    
    desc <<-DESC
      Stops the mysql cluster storage daemon on the data nodes
    DESC
    task :stop_data, :roles => :mysql_data do
      rsudo "service mysql-ndb stop"
    end
    
    desc <<-DESC
      Stops the mysql cluster sql daemon on the sql nodes
    DESC
    task :stop_sql, :roles => :mysql_sql do
      rsudo "service mysql stop"
    end
  
    desc <<-DESC
      Stops all the mysql cluster daemons
    DESC
    task :stop do
      stop_sql
      stop_data
      stop_mgm
    end
    
    desc <<-DESC
      Starts all the mysql cluster daemons
    DESC
    task :start do
      start_mgm
      start_data
      start_sql
    end
  
    desc <<-DESC
      Restarts all the mysql cluster daemons
    DESC
    task :restart do
      stop
      start
    end
    
  end

end
