namespace :rubber do

  # Add in some hooks so that we can insert our own hooks at head/tail of
  # hook chain - this is needed for making monit stop before everyone else.
  before "deploy:start", "rubber:pre_start"
  before "deploy:restart", "rubber:pre_restart"
  before "deploy:stop", "rubber:pre_stop"
  on :load do
    after "deploy:start", "rubber:post_start"
    after "deploy:restart", "rubber:post_restart"
    after "deploy:stop", "rubber:post_stop"
  end

  task :pre_start do
  end
  task :pre_restart do
  end
  task :pre_stop do
  end
  task :post_start do
  end
  task :post_restart do
  end
  task :post_stop do
  end

  # Don't want to do rubber:config for update_code as that tree isn't official
  # until it is 'committed' by the symlink task (and doing so causes it to run
  # for bootstrap_db which should only config the db config file).  However,
  # deploy:migrations doesn't call update, so we need an additional trigger for
  # it
  after "deploy:update", "rubber:config"
  after "deploy:rollback_code", "rubber:config"
  before "deploy:migrate", "rubber:config"

  desc <<-DESC
    Configures the deployed rails application by running the rubber configuration process
  DESC
  task :config do
    opts = {}
    opts['NO_POST'] = true if ENV['NO_POST']
    opts['FILE'] = ENV['FILE'] if ENV['FILE']
    opts['RUBBER_ENV'] = RUBBER_ENV
    # we need to set rails env as well because when running rake
    # in a rails project, rails gets loaded before the rubber hook gets run
    opts['RAILS_ENV'] = RUBBER_ENV

    # when running deploy:migrations, we need to run config against release_path
    opts[:deploy_path] = current_release if fetch(:migrate_target, :current).to_sym == :latest

    run_config(opts)
  end

  # because we start server as appserver user, but migrate as root, server needs to be able to write logs, etc.
  before "rubber:pre_start", "rubber:setup_app_permissions"
  before "rubber:pre_restart", "rubber:setup_app_permissions"

  desc <<-DESC
    Sets permissions of files in application directory to be owned by app_user.
  DESC
  task :setup_app_permissions do
    rsudo "find #{shared_path} -name cached-copy -prune -o -name bundle -prune -o -print0 | xargs -0 chown #{rubber_env.app_user}:#{rubber_env.app_user}"
    rsudo "chown -R #{rubber_env.app_user}:#{rubber_env.app_user} #{current_path}/tmp"
  end

  def run_config(options={})
    path = options.delete(:deploy_path) || current_path
    extra_env = options.keys.inject("") {|all, k|  "#{all} #{k}=\"#{options[k]}\""}

    # Need to do this so we can work with staging instances without having to
    # checkin instance file between create and bootstrap, as well as during a deploy
    if fetch(:push_instance_config, false)
      push_files = [rubber_instances.file] + rubber_cfg.environment.config_files
      push_files.each do |file|
        dest_file = file.sub(/^#{RUBBER_ROOT}\/?/, '')
        put(File.read(file), File.join(path, dest_file), :mode => "+r")
      end
    end

    # if the user has defined a secret config file, then push it into RUBBER_ROOT/config/rubber
    secret = rubber_cfg.environment.config_secret
    if secret && File.exist?(secret)
      base = rubber_cfg.environment.config_root.sub(/^#{RUBBER_ROOT}\/?/, '')
      put(File.read(secret), File.join(path, base, File.basename(secret)), :mode => "+r")
    end

    rsudo "cd #{path} && #{extra_env} #{fetch(:rake, 'rake')} rubber:config"
  end

end