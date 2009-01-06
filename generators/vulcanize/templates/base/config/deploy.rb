# This is a sample Capistrano config file for rubber

set :rails_env, (ENV["RAILS_ENV"] ||= 'production')

on :load do
  set :application, rubber_cfg.environment.bind().app_name
  set :deploy_to,     "/mnt/#{application}-#{rails_env}"
end

# Use a simple directory tree copy here to make demo easier.
# You probably want to use your own repository for a real app
set :scm, :none
set :repository, "."
set :deploy_via, :copy

# Easier to do system level config as root - probably should do it through
# sudo in the future.  We use ssh keys for access, so no passwd needed
set :user, 'root'
set :password, nil

# Use sudo with user rails for cap deploy:[stop|start|restart]
# This way exposed services (mongrel) aren't running as a privileged user
set :use_sudo,      true
set :runner,        'rails'

# How many old releases should be kept around when running "cleanup" task
set :keep_releases, 3

# Lets us work with staging instances without having to checkin config files
# (instance*.yml + rubber*.yml) for a deploy.  This gives us the
# convenience of not having to checkin files for staging, as well as 
# the safety of forcing it to be checked in for production.
set :push_instance_config, rails_env != 'production'

# Allows the tasks defined to fail gracefully if there are no hosts for them.
# Comment out or use "required_task" for default cap behavior of a hard failure
rubber.allow_optional_tasks(self)
# Wrap tasks in the deploy namespace that have roles so that we can use FILTER
# with something like a deploy:cold which tries to run deploy:migrate but can't
# because we filtered out the :db role
namespace :deploy do
  rubber.allow_optional_tasks(self)
  tasks.values.each do |t|
    if t.options[:roles]
      task t.name, t.options, &t.body
    end
  end
end

# =============================================================================
# TASKS
# =============================================================================


Dir["#{File.dirname(__FILE__)}/rubber/deploy-*.rb"].each do |deploy_file|
  load deploy_file
end

# Don't want to do rubber:config for update_code as that tree isn't official
# until it is 'committed' by the symlink task (and doing so causes it to run
# for bootstrap_db which should only config the db config file).  However, 
# deploy:migrations doesn't call update, so we need an additional trigger for
# it
after "deploy:update", "rubber:config"
after "deploy:rollback_code", "rubber:config"
before "deploy:migrate", "rubber:config"

before "rubber:pre_start", "setup_perms"
before "rubber:pre_restart", "setup_perms"
after "deploy", "deploy:cleanup"

# Fix perms because we start server as rails user, but migrate as root,
# server needs to be able to write logs, etc.
task :setup_perms do
  run "find #{shared_path} -name cached-copy -prune -o -print | xargs chown #{runner}:#{runner}"
  run "chown -R #{runner}:#{runner} #{current_path}/tmp"
end
