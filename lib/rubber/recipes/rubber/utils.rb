namespace :rubber do
    
  desc <<-DESC
    Convenience task for creating a staging instance for the given RUBBER_ENV/RAILS_ENV.
    By default this task assigns all known roles when creating the instance,
    but you can specify a different default in rubber.yml:staging_roles
    At the end, the instance will be up and running.  If the staging instance
    already exists, the user will be warned, and if they chose to proceed,
    will skip the create and just bootstrap that instance.
    e.g. RUBBER_ENV=matt cap create_staging
  DESC
  required_task :create_staging do
    if rubber_instances.size > 0
      value = Capistrano::CLI.ui.ask("The #{Rubber.env} environment already has instances, Are you SURE you want to create a staging instance that may interact with them [y/N]?: ")
      fatal("Exiting", 0) if value !~ /^y/
    end
    instance_alias = ENV['ALIAS'] = rubber.get_env("ALIAS", "Hostname to use for staging instance", true, Rubber.env)

    if rubber_instances[instance_alias]
      logger.info "Instance already exists, skipping to bootstrap"
    else
      default_roles = rubber_env.staging_roles
      roles = ENV['ROLES'] = rubber.get_env("ROLES", "Roles to use for staging instance", true, default_roles)
      
      rubber.create
    end

    # stop everything before so monit doesn't start stuff during bootstrapping
    # if its already installed due to a bundled instance
    deploy.stop rescue nil

    rubber.bootstrap
    
    # stop everything after in case package upgrades during bootstrap start up
    # services - we should be able to safely do a deploy:start below
    deploy.stop rescue nil

    # some bootstraps update code (bootstrap_db) but if you don't have that role, need to do it here
    # Since release directory variable gets reused by cap, we have to just do the symlink here - doing
    # a update again will fail
    if ! fetch(:rubber_code_was_updated, false)
      deploy.update_code
    end
    deploy.create_symlink
    deploy.migrate
    deploy.start
  end

  desc <<-DESC
    Destroy the staging instance for the given RUBBER_ENV.
  DESC
  task :destroy_staging do
    ENV['ALIAS'] = rubber.get_env("ALIAS", "Hostname of staging instance to be destroyed", true, Rubber.env)
    rubber.destroy
  end

  desc <<-DESC
    Live tail of rails log files for all machines
    By default tails the rails logs for the current RUBBER_ENV, but one can
    set FILE=/path/file.*.glob to tail a different set
  DESC
  task :tail_logs, :roles => :app do
    last_host = ""
    log_file_glob = rubber.get_env("FILE", "Log files to tail", true, "#{current_path}/log/#{Rubber.env}*.log")
    trap("INT") { puts 'Exiting...'; exit 0; }                    # handle ctrl-c gracefully
    run "tail -qf #{log_file_glob}" do |channel, stream, data|
      puts if channel[:host] != last_host                         # blank line between different hosts
      host = "[#{channel.properties[:host].gsub(/\..*/, '')}]"    # get left-most subdomain
      data.lines { |line| puts "%-15s %s" % [host, line] }        # add host name to the start of each line
      last_host = channel[:host]
      break if stream == :err
    end
  end

  # Use instead of task to define a capistrano task that runs serially instead of in parallel
  # The :groups option specifies how many groups to partition the servers into so that we can
  # do the task for N (= total/groups) servers at a time.  When multiple roles are supplied,
  # this tries to be intelligent and slice up each role independently, but runs the slices together
  # so that things don't take too long, e.g. adding an :api role to some :app servers, when restarting
  # you don't want to do the api first, then the others as this would take a long time, so instead
  # it does some :api and some :app, then some more of each
  #
  def serial_task(ns, name, options = {}, &block)
    # first figure out server names for the passed in roles - when no roles
    # are passed in, use all servers
    
    serial_roles = Array(options[:roles].respond_to?(:call) ? options[:roles].call() : options[:roles])
    servers = {}
    if serial_roles.empty?
      all_servers = top.roles.collect do |rolename, serverdefs|
        serverdefs.collect(&:host)
      end
      servers[:_serial_all] = all_servers.flatten.uniq.sort
    else
      # Get servers for each role
      top.roles.each do |rolename, serverdefs|
        if serial_roles.include?(rolename)
          servers[rolename] = serverdefs.collect(&:host)
        end
      end

      # Remove duplication of servers - roles which come first in list
      # have precedence, so the servers show up in that group
      added_servers = []
      serial_roles.each do |rolename|
        next if servers[rolename].nil?

        servers[rolename] -= added_servers
        added_servers.concat(servers[rolename])
        servers[rolename] = servers[rolename].uniq.sort
      end
    end

    # group each role's servers into slices and combine
    slices = []
    servers.each do |rolename, svrs|
      # figure out size of each slice by dividing server count by # of groups
      slice_size = (svrs.size.to_f / (options.delete(:groups) || 2)).round
      slice_size = 1 if slice_size < 1
      
      # add servers to slices
      slices += svrs.each_slice(slice_size).to_a
    end
    
    # for each slice, define a new task specific to the hosts in that slice
    task_syms = []
    slices.each do |server_group|
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
      instance = rubber_instances.find {|i| i.instance_id == instance_id }
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

  def prepare_script(name, contents, stop_on_error_cmd=rubber_env.stop_on_error_cmd, opts = {})
    script = "/tmp/#{name}"
    # this lets us abort a script if a command in the middle of it errors out
    contents = "#{stop_on_error_cmd}\n#{contents}" if stop_on_error_cmd
    put(contents, script, opts)
    return script
  end

  def run_script(name, contents, opts = {})
    args = opts.delete(:script_args)
    script = prepare_script(name, contents, rubber_env.stop_on_error_cmd, opts)
    run "bash #{script} #{args}", opts
  end

  def sudo_script(name, contents, opts = {})
    user = opts.delete(:as)
    args = opts.delete(:script_args)
    script = prepare_script(name, contents, rubber_env.stop_on_error_cmd, opts)

    sudo_args = user ? "-H -u #{user}" : ""
    run "#{sudo} #{sudo_args} bash -l #{script} #{args}", opts
  end

  def top.rsudo(command, opts = {}, &block)
    user = opts.delete(:as)
    args = "-H -u #{user}" if user
    run "#{sudo opts} #{args} bash -l -c '#{command}'", opts, &block
  end

  def get_env(name, desc, required=false, default=nil)
    value = ENV.delete(name)
    msg = "#{desc}"
    msg << " [#{default}]" if default
    msg << ": "
    value = Capistrano::CLI.ui.ask(msg) unless value
    value = value.size == 0 ? default : value
    fatal "#{name} is required, pass using environment or enter at prompt" if required && ! value

    # Explicitly convert to a String to avoid weird serialization issues with Psych.
    value.to_s
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
    rubber_instances.each do | ic|
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

  # some bootstraps update code (bootstrap_db), so keep track so we don't do it multiple times  
  after "deploy:update_code" do
    set :rubber_code_was_updated, true
  end
  
  def update_code_for_bootstrap
    unless (fetch(:rubber_code_was_updated, false))
      deploy.setup
      logger.info "updating code for bootstrap"
      deploy.update_code
    end
  end
  
end