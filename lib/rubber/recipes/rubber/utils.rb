namespace :rubber do
    
  desc <<-DESC
    Convenience task for creating a staging instance for the given RUBBER_ENV/RAILS_ENV.
    By default this task assigns all known roles when creating the instance,
    but you can specify a different default in rubber.yml:staging_roles
    At the end, the instance will be up and running
    e.g. RUBBER_ENV=matt cap create_staging
  DESC
  required_task :create_staging do
    if rubber_cfg.instance.size > 0
      value = Capistrano::CLI.ui.ask("The #{RUBBER_ENV} environment already has instances, Are you SURE you want to create a staging instance that may interact with them [y/N]?: ")
      fatal("Exiting", 0) if value !~ /^y/
    end
    instance_alias = ENV['ALIAS'] = rubber.get_env("ALIAS", "Hostname to use for staging instance", true, RUBBER_ENV)
    default_roles = rubber_cfg.environment.bind().staging_roles || "*"
    roles = ENV['ROLES'] = rubber.get_env("ROLES", "Roles to use for staging instance", true, default_roles)
    if rubber_cfg.instance[instance_alias]
      logger.info "Instance already exists, skipping to bootstrap"
    else
      rubber.create
    end
    rubber.bootstrap
    # stop everything in case we have a bundled instance with monit, etc starting at boot
    deploy.stop rescue nil
    # bootstrap_db does setup/update_code, so since release directory
    # variable gets reused by cap, we have to just do the symlink here - doing
    # a update again will fail
    deploy.symlink
    deploy.migrate
    deploy.start
  end

  desc <<-DESC
    Destroy the staging instance for the given RUBBER_ENV.
  DESC
  task :destroy_staging do
    ENV['ALIAS'] = rubber.get_env("ALIAS", "Hostname of staging instance to be destroyed", true, RUBBER_ENV)
    rubber.destroy
  end

  desc <<-DESC
    Live tail of rails log files for all machines
    By default tails the rails logs for the current RUBBER_ENV, but one can
    set FILE=/path/file.*.glob to tails a different set
  DESC
  task :tail_logs, :roles => :app do
    log_file_glob = rubber.get_env("FILE", "Log files to tail", true, "#{current_path}/log/#{RUBBER_ENV}*.log")
    run "tail -qf #{log_file_glob}" do |channel, stream, data|
      puts  # for an extra line break before the host name
      puts data
      break if stream == :err
    end
  end


  # Use instead of task to define a capistrano task that runs serially instead of in parallel
  # The :groups option specifies how many groups to partition the servers into so that we can
  # do the task for N (= total/groups) servers at a time
  def serial_task(ns, name, options = {}, &block)
    # first figure out server names for the passed in roles - when no roles
    # are passed in, use all servers
    serial_roles = Array(options[:roles])
    servers = []
    self.roles.each do |rolename, serverdefs|
      if serial_roles.empty? || serial_roles.include?(rolename)
        servers += serverdefs.collect {|server| server.host}
      end
    end
    servers = servers.uniq.sort

    # figure out size of each slice by deviding server count by # of groups
    slice_size = servers.size / (options.delete(:groups) || 2)
    slice_size = 1 if slice_size == 0

    # for each slice, define a new task sepcific to the hosts in that slice
    task_syms = []
    servers.each_slice(slice_size) do |server_group|
      servers = server_group.map{|s| s.gsub(/\..*/, '')}.join("_")
      task_sym = "_serial_task_#{name.to_s}_#{servers}".to_sym
      task_syms << task_sym
      ns.task task_sym, options.merge(:hosts => server_group), &block
    end

    # create the top level task that calls all the serial ones
    ns.task name, options do
      task_syms.each do |t|
        ns.send t
      end
    end
  end


  def find_alias(ip, instance_id, do_connect=true)
    if instance_id
      instance = rubber_cfg.instance.find {|i| i.instance_id == instance_id }
      local_alias = instance.full_name if instance
    end
    local_alias ||= File.read("/etc/hosts").grep(/#{ip}/).first.split[1] rescue nil
    if ! local_alias && do_connect
      task :_get_ip, :hosts => ip do
        local_alias = "* " + capture("hostname").strip
      end
      _get_ip rescue ConnectionError
    end
    return local_alias
  end

  def prepare_script(name, contents)
    script = "/tmp/#{name}"
    # this lets us abort a script if a command in the middle of it errors out
    env = rubber_cfg.environment.bind()
    contents = "#{env.stop_on_error_cmd}\n#{contents}" if env.stop_on_error_cmd
    put(contents, script)
    return script
  end

  def run_script(name, contents)
    script = prepare_script(name, contents)
    run "sh #{script}"
  end

  def sudo_script(name, contents)
    script = prepare_script(name, contents)
    sudo "sh #{script}"
  end

  def get_env(name, desc, required=false, default=nil)
    value = ENV.delete(name)
    msg = "#{desc}"
    msg << " [#{default}]" if default
    msg << ": "
    value = Capistrano::CLI.ui.ask(msg) unless value
    value = value.size == 0 ? default : value
    fatal "#{name} is required, pass using environment or enter at prompt" if required && ! value
    return value
  end

  def fatal(msg, code=1)
    logger.info msg
    exit code
  end

  # Returns a map of "hostvar_<hostname>" => value for the given config value for each instance host
  # This is used to run capistrano tasks scoped to the correct role/host so that a config value
  # specific to a role/host will only be used for that role/host, e.g. the list of packages to
  # be installed.
  def get_host_options(cfg_name, &block)
    opts = {}
    rubber_cfg.instance.each do | ic|
      env = rubber_cfg.environment.bind(ic.role_names, ic.name)
      cfg_value = env[cfg_name]
      if cfg_value
        if block
          cfg_value = block.call(cfg_value)
        end
        opts["hostvar_#{ic.full_name}"] = cfg_value if cfg_value && cfg_value.strip.size > 0
      end
    end
    return opts
  end

end