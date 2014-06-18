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

  namespace :config do

    desc <<-DESC
    Pushes and runs rubber configuration on the deployed rails application
    DESC
    task :default do
      # Don't want to do rubber:config during bootstrap_db where it's triggered by
      # deploy:update_code, because the user could be requiring the rails env inside
      # some of their config templates (which fails because rails can't connect to
      # the db)
      if fetch(:rubber_updating_code_for_bootstrap_db, false)
        logger.info "Updating code for bootstrap, skipping rubber:config"
      else
        rubber.config.push
        rubber.config.configure
      end
    end

    desc <<-DESC
    Pushes instance config and rubber secret file to remote
    DESC
    task :push do
      push_config
    end

    desc <<-DESC
    Configures the deployed rails application by running the rubber configuration process
    DESC
    task :configure do
      run_config
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

  def push_config
    unless fetch(:rubber_config_files_pushed, false)
      # Need to do this so we can work with staging instances without having to
      # checkin instance file between create and bootstrap, as well as during a deploy
      #
      # If we're not using an SCM to deploy, then the code must've been uploaded via
      # some strategy that would copy all the files from the local machine, so there's
      # no need to do a special file upload operation. That's only necessary when using an SCM
      # and not wanting to commit files in-progress.
      if fetch(:push_instance_config, false) && (fetch(:scm, nil) != :none)
        push_files = rubber_cfg.environment.config_files

        # If we're using a local instance file, push that up.  This isn't necessary when storing in S3 or SimpleDB.
        if rubber_instances.instance_storage =~ /^file:(.*)/
          location = $1
          push_files << location
        end

        push_files.each do |file|
          dest_file = file.sub(/^#{Rubber.root}\/?/, '')
          put(File.read(file), File.join(config_path, dest_file), :mode => "+r")
        end
      end

      # if the user has defined a secret config file, then push it into Rubber.root/config/rubber
      secret = rubber_cfg.environment.config_secret
      if secret && File.exist?(secret)
        base = rubber_cfg.environment.config_root.sub(/^#{Rubber.root}\/?/, '')
        put(File.read(secret), File.join(config_path, base, File.basename(secret)), :mode => "+r")
      end

      set :rubber_config_files_pushed, true
    end
  end

  def run_config(options={})
    path = options.delete(:deploy_path) || config_path
    no_post = options[:no_post] || ENV['NO_POST']
    force = options[:force] || ENV['FORCE']
    file = options[:file] || ENV['FILE']

    opts = ""
    opts += " --no_post" if no_post
    opts += " --force"   if force
    opts += " --file=\"#{file}\"" if file
    rsudo "cd #{path} && RUBBER_ENV=#{Rubber.env} RAILS_ENV=#{Rubber.env} ./script/rubber config #{opts}"
  end

  def config_path
    # when running deploy:migrations, we need to run config against release_path
    fetch(:migrate_target, :current).to_sym == :latest ? current_release : current_path
  end

end
