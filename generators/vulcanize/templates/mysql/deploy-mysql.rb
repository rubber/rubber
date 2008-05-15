
namespace :mysql do
  
  rubber.allow_optional_tasks(self)
  
  after "rubber:bootstrap", "mysql:bootstrap"

  desc <<-DESC
    Bootstrap the production database config.  Db bootstrap is special - the
    user could be requiring the rails env inside some of their config
    templates, which creates a catch 22 situation with the db, so we try and
    bootstrap the db separate from the rest of the config
  DESC
  task :bootstrap, :roles => :db do
    env = rubber_cfg.environment.bind("db", nil)
    if env.db_config
      # After everything installed on machines, we need the source tree
      # on hosts in order to run rubber:config for bootstrapping the db
      deploy.setup
      deploy.update_code
      # Gen mysql conf because we need a functioning db before we can migrate
      # Its up to user to create initial DB in mysql.cnf @post
      rubber.run_config(:RAILS_ENV => rails_env, :FILE => env.db_config, :deploy_path => release_path)
    end
  end

end