namespace :rubber do

  desc <<-DESC
    Create a new EC2 instance with the given ALIAS and ROLES
  DESC
  required_task :create do
    instance_aliases = get_env('ALIAS', "Instance alias (e.g. web01 or web01~web05,web09)", true)

    aliases = Rubber::Util::parse_aliases(instance_aliases)

    if aliases.size > 1
      default_roles = "roles for instance in *.yml"
      r = get_env("ROLES", "Instance roles (e.g. web,app,db:primary=true)", false, default_roles)
      r = "" if r == default_roles
    else
      env = rubber_cfg.environment.bind(nil, aliases.first)
      default_roles = env.instance_roles
      r = get_env("ROLES", "Instance roles (e.g. web,app,db:primary=true)", true, default_roles)
    end

    create_spot_instance = ENV.delete("SPOT_INSTANCE")

    if r == '*'
      instance_roles = rubber_cfg.environment.known_roles
      instance_roles = instance_roles.collect {|role| role == "db" ? "db:primary=true" : role }
    else
      instance_roles = r.split(",")
    end
    
    create_instances(aliases, instance_roles, create_spot_instance)
  end

  desc <<-DESC
    Refresh the host data for a EC2 instance with the given ALIAS.
    This is useful to run when rubber:create fails after instance creation
  DESC
  required_task :refresh do
    instance_aliases = get_env('ALIAS', "Instance alias (e.g. web01 or web01~web05,web09)", true)

    aliases = Rubber::Util::parse_aliases(instance_aliases)

    ENV.delete('ROLES') # so we don't get an error if people leave ROLES in env from :create CLI
    
    refresh_instances(aliases)
  end

  desc <<-DESC
    Destroy the EC2 instance for the given ALIAS
  DESC
  required_task :destroy do
    instance_aliases = get_env('ALIAS', "Instance alias (e.g. web01 or web01~web05,web09)", true)

    aliases = Rubber::Util::parse_aliases(instance_aliases)

    ENV.delete('ROLES') # so we don't get an error if people leave ROLES in env from :create CLI
    destroy_instances(aliases, ENV['FORCE'] == 'true')
  end

  desc <<-DESC
    Destroy ALL the EC2 instances for the current env
  DESC
  required_task :destroy_all do
    rubber_instances.each do |ic|
      destroy_instance(ic.name, ENV['FORCE'] == 'true')
    end
  end

  desc <<-DESC
    Reboot the EC2 instance for the give ALIAS
  DESC
  required_task :reboot do
    instance_alias = get_env('ALIAS', "Instance alias (e.g. web01)", true)
    ENV.delete('ROLES') # so we don't get an error if people leave ROLES in env from :create CLI
    reboot_instance(instance_alias)
  end

  desc <<-DESC
    Stop the EC2 instance for the give ALIAS
  DESC
  required_task :stop do
    instance_alias = get_env('ALIAS', "Instance alias (e.g. web01)", true)
    ENV.delete('ROLES') # so we don't get an error if people leave ROLES in env from :create CLI
    stop_instance(instance_alias)
  end

  desc <<-DESC
    Start the EC2 instance for the give ALIAS
  DESC
  required_task :start do
    instance_alias = get_env('ALIAS', "Instance alias (e.g. web01)", true)
    ENV.delete('ROLES') # so we don't get an error if people leave ROLES in env from :create CLI
    start_instance(instance_alias)
  end

  desc <<-DESC
    Adds the given ROLES to the instance named ALIAS
  DESC
  required_task :add_role do
    instance_alias = get_env('ALIAS', "Instance alias (e.g. web01)", true)
    r = get_env('ROLES', "Instance roles (e.g. web,app,db:primary=true)", true)

    instance_roles = r.split(",")

    ir = []
    instance_roles.each do |r|
      role = Rubber::Configuration::RoleItem.parse(r)
      ir << role
    end

    # Add in roles that the given set of roles depends on
    ir = Rubber::Configuration::RoleItem.expand_role_dependencies(ir, get_role_dependencies)

    instance = rubber_instances[instance_alias]
    fatal "Instance does not exist: #{instance_alias}" unless instance

    instance.roles = (instance.roles + ir).uniq
    rubber_instances.save()
    logger.info "Roles for #{instance_alias} are now:"
    logger.info instance.role_names.sort.join("\n")
    logger.info ''
    logger.info "Run 'cap rubber:bootstrap' if done adding roles"
  end

  desc <<-DESC
    Removes the given ROLES from the instance named ALIAS
  DESC
  required_task :remove_role do
    instance_alias = get_env('ALIAS', "Instance alias (e.g. web01)", true)
    r = get_env('ROLES', "Instance roles (e.g. web,app,db:primary=true)", true)

    instance_roles = r.split(",")

    ir = []
    instance_roles.each do |r|
      role = Rubber::Configuration::RoleItem.parse(r)
      ir << role
    end

    instance = rubber_instances[instance_alias]
    fatal "Instance does not exist: #{instance_alias}" unless instance

    instance.roles = (instance.roles - ir).uniq
    rubber_instances.save()
    logger.info "Roles for #{instance_alias} are now:"
    logger.info instance.role_names.sort.join("\n")
  end

  desc <<-DESC
    List all your EC2 instances
  DESC
  required_task :describe do
    results = []
    format = "%-10s %-10s %-10s %-15s %-30s"
    results << format % %w[InstanceID State Zone IP Alias\ (*=unknown)]

    instances = cloud.describe_instances()
    instances.each do |instance|
      local_alias = find_alias(instance[:external_ip], instance[:id], instance[:state] == 'running')
      results << format % [instance[:id], instance[:state], instance[:zone], instance[:external_ip] || "NoIP", local_alias || "Unknown"]
    end
    results.each {|r| logger.info r}
  end

  desc <<-DESC
    Describes the availability zones
  DESC
  required_task :describe_zones do
    results = []
    format = "%-20s %-15s"
    results << format % %w[Name State]

    zones = cloud.describe_availability_zones()
    zones.each do |zone|
      results << format % [zone[:name], zone[:state]]
    end

    results.each {|r| logger.info r}
  end

  set :print_ip_command, "ifconfig eth0 | awk 'NR==2 {print $2}' | awk -F: '{print $2}'"

  # Creates the set of new instancea after figuring out the roles for each
  def create_instances(instance_aliases, instance_roles, create_spot_instance=false)
    creation_threads = []
    refresh_threads = []

    instance_aliases.each do |instance_alias|
      fatal "Instance already exists: #{instance_alias}" if rubber_instances[instance_alias]

      ir = []

      roles = instance_roles
      if roles.size == 0
        env = rubber_cfg.environment.bind(nil, instance_alias)
        roles = env.instance_roles.split(",") rescue []
      end

      roles.each do |r|
        role = Rubber::Configuration::RoleItem.parse(r)

        # If user doesn't setup a primary db, then be nice and do it
        if role.name == "db" && role.options["primary"] == nil && rubber_instances.for_role("db").size == 0
          value = Capistrano::CLI.ui.ask("You do not have a primary db role, should #{instance_alias} be it [y/n]?: ")
          role.options["primary"] = true if value =~ /^y/
        end

        ir << role
      end

      # Add in roles that the given set of roles depends on
      ir = Rubber::Configuration::RoleItem.expand_role_dependencies(ir, get_role_dependencies)

      creation_threads << Thread.new do
        create_instance(instance_alias, ir, create_spot_instance)

        refresh_threads << Thread.new do
          while ! refresh_instance(instance_alias)
            sleep 1
          end
        end
      end

      sleep 2
    end
    
    creation_threads.each {|t| t.join }

    print "Waiting for instances to start"

    while true do
      print "."
      sleep 2

      break if refresh_threads.all? {|t| ! t.alive? }
    end

    refresh_threads.each {|t| t.join }

    post_refresh
  end

  set :mutex, Mutex.new

  # Creates a new ec2 instance with the given alias and roles
  # Configures aliases (/etc/hosts) on local and remote machines
  def create_instance(instance_alias, instance_roles, create_spot_instance)
    role_names = instance_roles.collect{|x| x.name}
    env = rubber_cfg.environment.bind(role_names, instance_alias)

    # We need to use security_groups during create, so create them up front
    mutex.synchronize do
      setup_security_groups(instance_alias, role_names)
    end
    security_groups = get_assigned_security_groups(instance_alias, role_names)

    ami = env.cloud_providers[env.cloud_provider].image_id
    ami_type = env.cloud_providers[env.cloud_provider].image_type
    availability_zone = env.availability_zone

    create_spot_instance ||= env.cloud_providers[env.cloud_provider].spot_instance

    if create_spot_instance
      spot_price = env.cloud_providers[env.cloud_provider].spot_price.to_s

      logger.info "Creating spot instance request for instance #{ami}/#{ami_type}/#{security_groups.join(',') rescue 'Default'}/#{availability_zone || 'Default'}"
      request_id = cloud.create_spot_instance_request(spot_price, ami, ami_type, security_groups, availability_zone)

      print "Waiting for spot instance request to be fulfilled"
      max_wait_time = env.cloud_providers[env.cloud_provider].spot_instance_request_timeout || (1.0 / 0) # Use the specified timeout value or default to infinite.
      instance_id = nil
      while instance_id.nil? do
        print "."
        sleep 2
        max_wait_time -= 2

        request = cloud.describe_spot_instance_requests(request_id).first
        instance_id = request[:instance_id]

        if max_wait_time < 0 && instance_id.nil?
          cloud.destroy_spot_instance_request(request[:id])

          print "\n"
          print "Failed to fulfill spot instance in the time specified. Falling back to on-demand instance creation."
          break
        end
      end

      print "\n"
    end

    if !create_spot_instance || (create_spot_instance && max_wait_time < 0)
      logger.info "Creating instance #{ami}/#{ami_type}/#{security_groups.join(',') rescue 'Default'}/#{availability_zone || 'Default'}"
      instance_id = cloud.create_instance(ami, ami_type, security_groups, availability_zone)
    end

    logger.info "Instance #{instance_alias} created: #{instance_id}"

    instance_item = Rubber::Configuration::InstanceItem.new(instance_alias, env.domain, instance_roles, instance_id, ami_type, ami, security_groups)
    instance_item.spot_instance_request_id = request_id if create_spot_instance
    rubber_instances.add(instance_item)
    rubber_instances.save()

    # Sometimes tag creation will fail, indicating that the instance doesn't exist yet even though it does.  It seems to
    # be a propagation delay on Amazon's end, so the best we can do is wait and try again.
    begin
      Rubber::Tag::update_instance_tags(instance_alias)
    rescue Exception
      sleep 0.5
      retry
    end
  end

  def refresh_instances(instance_aliases)
    refresh_threads = []

    instance_aliases.each do |instance_alias|
      refresh_threads << Thread.new do
        while ! refresh_instance(instance_alias)
          sleep 1
        end
      end
    end

    refresh_threads.each {|t| t.join }

    post_refresh
  end

  # Refreshes a ec2 instance with the given alias
  # Configures aliases (/etc/hosts) on local and remote machines
  def refresh_instance(instance_alias)
    instance_item = rubber_instances[instance_alias]

    fatal "Instance does not exist: #{instance_alias}" if ! instance_item

    env = rubber_cfg.environment.bind(instance_item.role_names, instance_alias)

    instance = cloud.describe_instances(instance_item.instance_id).first rescue {}

    if instance[:state] == "running"
      print "\n"
      logger.info "Instance running, fetching hostname/ip data"
      instance_item.external_host = instance[:external_host]
      instance_item.external_ip = instance[:external_ip]
      instance_item.internal_host = instance[:internal_host]
      instance_item.internal_ip = instance[:internal_ip]
      instance_item.zone = instance[:zone]
      instance_item.platform = instance[:platform]
      instance_item.root_device_type = instance[:root_device_type]
      rubber_instances.save()

      unless instance_item.windows?
        # weird cap/netssh bug, sometimes just hangs forever on initial connect, so force a timeout
        begin
          Timeout::timeout(30) do
            # turn back on root ssh access if we are using root as the capistrano user for connecting
            enable_root_ssh(instance_item.external_ip, fetch(:initial_ssh_user, 'ubuntu')) if user == 'root'
            # force a connection so if above isn't enabled we still timeout if initial connection hangs
            direct_connection(instance_item.external_ip) do
              run "echo"
            end
          end
        rescue Timeout::Error
          logger.info "timeout in initial connect, retrying"
          retry
        end
      end

      return true
    end
    return false
  end

  def post_refresh
    env = rubber_cfg.environment.bind(nil, nil)

    # setup amazon elastic ips if configured to do so
    setup_static_ips

    # Need to setup aliases so ssh doesn't give us errors when we
    # later try to connect to same ip but using alias
    setup_local_aliases

    # re-load the roles since we may have just defined new ones
    load_roles() unless env.disable_auto_roles
    
    rubber_instances.save()

    # Add the aliases for this instance to all other hosts
    setup_remote_aliases
    setup_dns_aliases
  end

  def destroy_instances(instance_aliases, force=false)
    instance_aliases.each do |instance_alias|
      destroy_instance(instance_alias, force)
    end

    post_destroy
  end

  # Destroys the given ec2 instance
  def destroy_instance(instance_alias, force=false)
    instance_item = rubber_instances[instance_alias]
    fatal "Instance does not exist: #{instance_alias}" if ! instance_item

    env = rubber_cfg.environment.bind(instance_item.role_names, instance_item.name)

    value = Capistrano::CLI.ui.ask("About to DESTROY #{instance_alias} (#{instance_item.instance_id}) in mode #{RUBBER_ENV}.  Are you SURE [yes/NO]?: ") unless force
    fatal("Exiting", 0) if value != "yes" && ! force

    if instance_item.static_ip
      value = Capistrano::CLI.ui.ask("Instance has a static ip, do you want to release it? [y/N]?: ") unless force
      destroy_static_ip(instance_item.static_ip) if value =~ /^y/ || force
    end

    if instance_item.volumes
      value = Capistrano::CLI.ui.ask("Instance has persistent volumes, do you want to destroy them? [y/N]?: ") unless force
      if value =~ /^y/ || force
        instance_item.volumes.clone.each do |volume_id|
          destroy_volume(volume_id)
        end
      end
    end

    logger.info "Destroying instance alias=#{instance_alias}, instance_id=#{instance_item.instance_id}"

    cloud.destroy_instance(instance_item.instance_id)

    rubber_instances.remove(instance_alias)
    rubber_instances.save()

    destroy_dyndns(instance_item)
    cleanup_known_hosts(instance_item) unless env.disable_known_hosts_cleanup
  end

  def post_destroy
    env = rubber_cfg.environment.bind(nil, nil)
    
    # re-load the roles since we just removed some and setup_remote_aliases
    # shouldn't hit removed ones
    load_roles() unless env.disable_auto_roles

    setup_aliases
  end
  
  # Reboots the given ec2 instance
  def reboot_instance(instance_alias)
    instance_item = rubber_instances[instance_alias]
    fatal "Instance does not exist: #{instance_alias}" if ! instance_item

    env = rubber_cfg.environment.bind(instance_item.role_names, instance_item.name)

    value = Capistrano::CLI.ui.ask("About to REBOOT #{instance_alias} (#{instance_item.instance_id}) in mode #{RUBBER_ENV}.  Are you SURE [yes/NO]?: ")
    fatal("Exiting", 0) if value != "yes"

    logger.info "Rebooting instance alias=#{instance_alias}, instance_id=#{instance_item.instance_id}"

    cloud.reboot_instance(instance_item.instance_id)
  end

  # Stops the given ec2 instance.  Note that this operation only works for instances that use an EBS volume for the root
  # device and that are not spot instances.
  def stop_instance(instance_alias)
    instance_item = rubber_instances[instance_alias]
    fatal "Instance does not exist: #{instance_alias}" if ! instance_item
    fatal "Cannot stop spot instances!" if ! instance_item.spot_instance_request_id.nil?
    fatal "Cannot stop instances with instance-store root device!" if (instance_item.root_device_type != 'ebs')

    env = rubber_cfg.environment.bind(instance_item.role_names, instance_item.name)

    value = Capistrano::CLI.ui.ask("About to STOP #{instance_alias} (#{instance_item.instance_id}) in mode #{RUBBER_ENV}.  Are you SURE [yes/NO]?: ")
    fatal("Exiting", 0) if value != "yes"

    logger.info "Stopping instance alias=#{instance_alias}, instance_id=#{instance_item.instance_id}"

    cloud.stop_instance(instance_item.instance_id)
  end

  # Starts the given ec2 instance.  Note that this operation only works for instances that use an EBS volume for the root
  # device, that are not spot instances, and that are already stopped.
  def start_instance(instance_alias)
    instance_item = rubber_instances[instance_alias]
    fatal "Instance does not exist: #{instance_alias}" if ! instance_item
    fatal "Cannot start spot instances!" if ! instance_item.spot_instance_request_id.nil?
    fatal "Cannot start instances with instance-store root device!" if (instance_item.root_device_type != 'ebs')

    env = rubber_cfg.environment.bind(instance_item.role_names, instance_item.name)

    value = Capistrano::CLI.ui.ask("About to START #{instance_alias} (#{instance_item.instance_id}) in mode #{RUBBER_ENV}.  Are you SURE [yes/NO]?: ")
    fatal("Exiting", 0) if value != "yes"

    logger.info "Starting instance alias=#{instance_alias}, instance_id=#{instance_item.instance_id}"

    cloud.start_instance(instance_item.instance_id)

    # Re-starting an instance will almost certainly give it a new set of IPs and DNS entries, so refresh the values.
    print "Waiting for instance to start"
    while true do
      print "."
      sleep 2

      break if refresh_instance(instance_alias)
    end
  end

  # delete from ~/.ssh/known_hosts all lines that begin with ec2- or instance_alias
  def cleanup_known_hosts(instance_item)
    logger.info "Cleaning ~/.ssh/known_hosts"
    File.open(File.expand_path('~/.ssh/known_hosts'), 'r+') do |f|
        out = ""
        f.each do |line|
          line = case line
            when /^ec2-/; ''
            when /#{instance_item.full_name}/; ''
            when /#{instance_item.external_host}/; ''
            when /#{instance_item.external_ip}/; ''
            else line;
          end
          out << line
        end
        f.pos = 0
        f.print out
        f.truncate(f.pos)
    end
  end

  def get_role_dependencies
    # convert string format of role_dependencies from rubber.yml into
    # objects for use by expand_role_dependencies
    deps = {}
    rubber_env.role_dependencies.each do |k, v|
      rhs = Array(v).collect {|r| Rubber::Configuration::RoleItem.parse(r)}
      deps[Rubber::Configuration::RoleItem.parse(k)] = rhs
    end if rubber_env.role_dependencies
    return deps
  end
  
end
