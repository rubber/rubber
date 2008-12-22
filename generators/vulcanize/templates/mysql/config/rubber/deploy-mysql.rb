
namespace :rubber do
  
  namespace :mysql do
    
    rubber.allow_optional_tasks(self)
    
    after "rubber:create", "rubber:mysql:set_db_role"
      
    # Capistrano needs db:primary role for migrate to work
    task :set_db_role do
      db_instances = rubber_cfg.instance.for_role("mysql_master")
      db_instances.each do |instance|
        if ! instance.role_names.find {|n| n == 'db'}
          role = Rubber::Configuration::RoleItem.new('db')
          primary_exists = rubber_cfg.instance.for_role("db", "primary" => true).size > 0
          role.options["primary"] = true  unless primary_exists
          instance.roles << role
        end
      end
      db_instances = rubber_cfg.instance.for_role("mysql_slave")
      db_instances.each do |instance|
        if instance.role_names.find {|n| n == 'mysql_master'}
          logger.info "Cannot have a mysql slave and master on the same instance, removing slave role"
          instance.roles.delete_if {|r| r.name == 'mysql_slave'}
          next
        end
        if ! instance.role_names.find {|n| n == 'db'}
          role = Rubber::Configuration::RoleItem.new('db')
          instance.roles << role
        end
      end
      rubber_cfg.instance.save()
      load_roles() unless rubber_cfg.environment.bind().disable_auto_roles
    end
  
    after "rubber:bootstrap", "rubber:mysql:bootstrap"
  
    
    # Bootstrap the production database config.  Db bootstrap is special - the
    # user could be requiring the rails env inside some of their config
    # templates, which creates a catch 22 situation with the db, so we try and
    # bootstrap the db separate from the rest of the config
    task :bootstrap, :roles => [:mysql_master, :mysql_slave] do
      
      # Conditionaly bootstrap for each node/role only if that node has not
      # been boostrapped for that role before
      
      master_instances = rubber_cfg.instance.for_role("mysql_master") & rubber_cfg.instance.filtered  
      master_instances.each do |ic|
        task_name = "_bootstrap_mysql_master_#{ic.full_name}".to_sym()
        task task_name, :hosts => ic.full_name do
          env = rubber_cfg.environment.bind("mysql_master", ic.name)
          exists = capture("echo $(ls -d #{env.db_data_dir} 2> /dev/null)")
          if exists.strip.size == 0
            common_bootstrap("mysql_master")
            sudo "dpkg-reconfigure --frontend=noninteractive mysql-server-5.0"
            sleep 5
            pass = "identified by '#{env.db_pass}'" if env.db_pass
            sudo "mysql -u root -e 'create database #{env.db_name};'"
            sudo "mysql -u root -e \"grant all on *.* to '#{env.db_user}'@'%' #{pass};\""
            sudo "mysql -u root -e \"grant select on *.* to '#{env.db_slave_user}'@'%' #{pass};\""
            sudo "mysql -u root -e \"grant replication slave on *.* to '#{env.db_replicator_user}'@'%' #{pass};\""
            sudo "mysql -u root -e \"flush privileges;\""
          end
        end
        send task_name
      end
    
      slave_instances = rubber_cfg.instance.for_role("mysql_slave") & rubber_cfg.instance.filtered  
      slave_instances.each do |ic|
        task_name = "_bootstrap_mysql_slave_#{ic.full_name}".to_sym()
        task task_name, :hosts => ic.full_name do
          env = rubber_cfg.environment.bind("mysql_slave", ic.name)
          exists = capture("echo $(ls -d #{env.db_data_dir} 2> /dev/null)")
          if exists.strip.size == 0
            common_bootstrap("mysql_slave")
            sudo "dpkg-reconfigure --frontend=noninteractive mysql-server-5.0"
            sleep 5
            pass = "identified by '#{env.db_pass}'" if env.db_pass
            master_pass = ", master_password='#{env.db_pass}'" if env.db_pass
            master = rubber_cfg.instance.for_role("db", "primary" => true).first.full_name
            sudo "mysql -u root -e \"change master to master_host='#{master}', master_user='#{env.db_replicator_user}' #{master_pass}\""
            sudo "mysqldump -u #{env.db_user} #{pass} -h #{master} --all-databases --master-data=1 | mysql -u root"
            sudo "mysql -u root -e \"start slave;\""
          end
        end
        send task_name
      end
      
    end
  
    # TODO: Make the setup/update happen just once per host
    def common_bootstrap(role)
      # mysql package install starts mysql, so stop it
      sudo "/etc/init.d/mysql stop" rescue nil
      
      # After everything installed on machines, we need the source tree
      # on hosts in order to run rubber:config for bootstrapping the db
      deploy.setup
      deploy.update_code
      
      # Gen just the conf for the given mysql role
      rubber.run_config(:RAILS_ENV => rails_env, :FILE => "role/#{role}|role/db/my.cnf", :deploy_path => release_path)
    end
    
    desc <<-DESC
      Starts the mysql daemons
    DESC
    task :start, :roles => [:mysql_master, :mysql_slave] do
      sudo "/etc/init.d/mysql start"
    end
    
    desc <<-DESC
      Stops the mysql daemons
    DESC
    task :stop, :roles => [:mysql_master, :mysql_slave] do
      sudo "/etc/init.d/mysql stop"
    end
  
    desc <<-DESC
      Restarts the mysql daemons
    DESC
    task :restart, :roles => [:mysql_master, :mysql_slave] do
      sudo "/etc/init.d/mysql restart"
    end
  
  end

end