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

  after "deploy:update", "rubber:config"
  after "deploy:rollback_code", "rubber:config"
  before "deploy:migrate", "rubber:config"

  desc <<-DESC
    Configures the deployed rails application by running the rubber configuration process
  DESC
  task :config do
    # Don't want to do rubber:config during bootstrap_db where it's triggered by
    # deploy:update_code, because the user could be requiring the rails env inside
    # some of their config templates (which fails because rails can't connect to
    # the db)
    if fetch(:rubber_updating_code_for_bootstrap_db, false)
      logger.info "Updating code for bootstrap, skipping rubber:config"
    else
      opts = {}
      opts[:no_post] = true if ENV['NO_POST']
      opts[:force] = true if ENV['FORCE']
      opts[:file] = ENV['FILE'] if ENV['FILE']

      # when running deploy:migrations, we need to run config against release_path
      opts[:deploy_path] = current_release if fetch(:migrate_target, :current).to_sym == :latest

      run_config(opts)
    end
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
    opts = ""
    opts += " --no_post" if options[:no_post]
    opts += " --force" if options[:force]
    opts += " --file=\"#{options[:file]}\"" if options[:file]

    # Need to do this so we can work with staging instances without having to
    # checkin instance file between create and bootstrap, as well as during a deploy
    if fetch(:push_instance_config, false)
      push_files = rubber_cfg.environment.config_files

      # If we're using a local instance file, push that up.  This isn't necessary when storing in S3 or SimpleDB.
      if rubber_instances.instance_storage =~ /^file:(.*)/
        location = $1
        push_files << location
      end

      push_files.each do |file|
        dest_file = file.sub(/^#{Rubber.root}\/?/, '')
        put(File.read(file), File.join(path, dest_file), :mode => "+r")
      end
    end

    # if the user has defined a secret config file, then push it into Rubber.root/config/rubber
    secret = rubber_cfg.environment.config_secret
    if secret && File.exist?(secret)
      base = rubber_cfg.environment.config_root.sub(/^#{Rubber.root}\/?/, '')
      put(File.read(secret), File.join(path, base, File.basename(secret)), :mode => "+r")
    end
    
    rsudo "cd #{path} && RUBBER_ENV=#{Rubber.env} RAILS_ENV=#{Rubber.env} ./script/rubber config #{opts}"
  end

end