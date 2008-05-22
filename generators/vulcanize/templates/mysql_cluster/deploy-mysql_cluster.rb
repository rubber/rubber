
namespace :mysql_cluster do
  
  rubber.allow_optional_tasks(self)

  after "rubber:create", "mysql_cluster:set_db_role"
    
  # Capistrano needs db:primary role for migrate to work
  task :set_db_role do
    sql_instances = rubber_cfg.instance.for_role("mysql_sql")
    sql_instances.each do |instance|
      if ! instance.role_names.find {|n| n == 'db'}
        role = Rubber::Configuration::RoleItem.new('db')
        primary_exists = rubber_cfg.instance.for_role("db", "primary" => true).size > 0
        role.options["primary"] = true  unless primary_exists
        instance.roles << role
        rubber_cfg.instance.save()
      end
    end
  end
    
  after "rubber:bootstrap", "mysql_cluster:bootstrap"

  task :bootstrap, :roles => :mysql_data do
    # Conditionaly bootstrap for each node/role only if that node has not
    # been boostrapped for that role before

    rubber_cfg.instance.for_role("mysql_mgm").each do |ic|
      task_name = "_bootstrap_mysql_mgm_#{ic.full_name}".to_sym()
      task task_name, :host => ic.full_name do
        exists = capture("if grep -c rubber.*mysql_mgm /etc/mysql/ndb_mgmd.cnf &> /dev/null; then echo exists; fi")
        if exists.strip.size == 0
          common_bootstrap("mysql_mgm")
          sudo "/etc/init.d/mysql-ndb-mgm start"
        end
      end
      send task_name
    end
      rubber_cfg.instance.for_role("mysql_data").each do |ic|
      task_name = "_bootstrap_mysql_data_#{ic.full_name}".to_sym()
      task task_name, :host => ic.full_name do
        exists = capture("if grep -c rubber.*mysql_data /etc/mysql/my.cnf &> /dev/null; then echo exists; fi")
        if exists.strip.size == 0
          common_bootstrap("mysql_data")
          sudo "/etc/init.d/mysql-ndb start-initial"
        end
      end
      send task_name
    end
    
    rubber_cfg.instance.for_role("mysql_sql").each do |ic|
      task_name = "_bootstrap_mysql_sql_#{ic.full_name}".to_sym()
      task task_name, :host => ic.full_name do
        exists = capture("if grep -c rubber.*mysql_sql /etc/mysql/my.cnf &> /dev/null; then echo exists; fi")
        if exists.strip.size == 0
          common_bootstrap("mysql_sql")
          sudo "/etc/init.d/mysql start"
          env = rubber_cfg.environment.bind()
          # For mysql 5.0 cluster, need to create users and database for EVERY sql node
          pass = "identified by '#{env.db_pass}'" if env.db_pass
          sudo "mysql -u root -e 'create database #{env.db_name};'"
          sudo "mysql -u root -e \"grant all on #{env.db_name}.* to '#{env.db_user}'@'%' #{pass};\""
          sudo "mysql -u root -e \"update user set Super_priv = 'N' where user = '#{env.db_user}';\" mysql"
        end
      end
      send task_name
    end
    
  end

  def common_bootstrap(role)
    # mysql package install starts mysql, so stop it
    sudo "/etc/init.d/mysql stop" rescue nil
    
    # After everything installed on machines, we need the source tree
    # on hosts in order to run rubber:config for bootstrapping the db
    deploy.setup
    deploy.update_code
    
    # Gen just the conf for the given mysql role
    rubber.run_config(:RAILS_ENV => rails_env, :FILE => "role/#{role}", :deploy_path => release_path)
  end
  
  desc <<-DESC
    Starts the mysql cluster management daemon on the management node
  DESC
  task :start_mgm, :roles => :mysql_mgm do
    sudo "/etc/init.d/mysql-ndb-mgm start"
  end
  
  desc <<-DESC
    Starts the mysql cluster storage daemon on the data nodes
  DESC
  task :start_data, :roles => :mysql_data do
    sudo "/etc/init.d/mysql-ndb start"
  end
  
  desc <<-DESC
    Starts the mysql cluster sql daemon on the sql nodes
  DESC
  task :start_sql, :roles => :mysql_sql do
    sudo "/etc/init.d/mysql start"
  end
  
  desc <<-DESC
    Stops the mysql cluster management daemon on the management node
  DESC
  task :stop_mgm, :roles => :mysql_mgm do
    sudo "/etc/init.d/mysql-ndb-mgm stop"
  end
  
  desc <<-DESC
    Stops the mysql cluster storage daemon on the data nodes
  DESC
  task :stop_data, :roles => :mysql_data do
    sudo "/etc/init.d/mysql-ndb stop"
  end
  
  desc <<-DESC
    Stops the mysql cluster sql daemon on the sql nodes
  DESC
  task :stop_sql, :roles => :mysql_sql do
    sudo "/etc/init.d/mysql stop"
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
