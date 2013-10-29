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
      instance_roles = rubber_cfg.environment.known_roles.reject {|r| r =~ /slave/ || r =~ /^db$/ }
    else
      instance_roles = r.split(/\s*,\s*/)
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
    destroy_instances(aliases, ENV['FORCE'] =~ /^(t|y)/)
  end

  desc <<-DESC
    Destroy ALL the EC2 instances for the current env
  DESC
  required_task :destroy_all do
    rubber_instances.each do |ic|
      destroy_instance(ic.name, ENV['FORCE'] =~ /^(t|y)/)
    end
  end

  desc <<-DESC
    Reboot the EC2 instance for the give ALIAS
  DESC
  required_task :reboot do
    instance_aliases = get_env('ALIAS', "Instance alias (e.g. web01 or web01~web05,web09)", true)
    
    aliases = Rubber::Util::parse_aliases(instance_aliases)
    ENV.delete('ROLES') # so we don't get an error if people leave ROLES in env from :create CLI
    reboot_instances(aliases, ENV['FORCE'] =~ /^(t|y)/)
  end

  desc <<-DESC
    Stop the EC2 instance for the give ALIAS
  DESC
  required_task :stop do
    instance_aliases = get_env('ALIAS', "Instance alias (e.g. web01 or web01~web05,web09)", true)
    
    aliases = Rubber::Util::parse_aliases(instance_aliases)
    ENV.delete('ROLES') # so we don't get an error if people leave ROLES in env from :create CLI
    stop_instances(aliases)
  end

  desc <<-DESC
    Start the EC2 instance for the give ALIAS
  DESC
  required_task :start do
    instance_aliases = get_env('ALIAS', "Instance alias (e.g. web01 or web01~web05,web09)", true)

    aliases = Rubber::Util::parse_aliases(instance_aliases)
    ENV.delete('ROLES') # so we don't get an error if people leave ROLES in env from :create CLI
    start_instances(aliases)
  end

  namespace :roles do
    rubber.allow_optional_tasks(self)
    
    desc <<-DESC
      Adds the given ROLES to the instance named ALIAS
    DESC
    required_task :add do
      instance_alias = get_env('ALIAS', "Instance alias (e.g. web01)", true)
      roles_string = get_env('ROLES', "Instance roles (e.g. web,app,db:primary=true)", true)
      
      instance = rubber_instances[instance_alias]
      fatal "Instance does not exist: #{instance_alias}" unless instance
    
      # Parse roles_string into an Array of roles
      ir = roles_string.split(/\s*,\s*/).collect{|r| Rubber::Configuration::RoleItem.parse(r)}
    
      # Add in roles that the given set of roles depends on
      ir = Rubber::Configuration::RoleItem.expand_role_dependencies(ir, get_role_dependencies)
    
      instance.roles = (instance.roles + ir).uniq
      rubber_instances.save()
      logger.info "Roles for #{instance_alias} are now:"
      logger.info instance.roles.collect(&:to_s).sort.join("\n")
      logger.info ''
      logger.info "Run 'cap rubber:bootstrap' if done adding roles"
    end

    desc <<-DESC
      Removes the given ROLES from the instance named ALIAS
    DESC
    required_task :remove do
      instance_alias = get_env('ALIAS', "Instance alias (e.g. web01)", true)
      roles_string = get_env('ROLES', "Instance roles (e.g. web,app,db:primary=true)", true)
      
      instance = rubber_instances[instance_alias]
      fatal "Instance does not exist: #{instance_alias}" unless instance
    
      # Parse roles_string into an Array of roles
      ir = roles_string.split(/\s*,\s*/).collect{|r| Rubber::Configuration::RoleItem.parse(r)}
    
      instance.roles = (instance.roles - ir).uniq
      rubber_instances.save()
      logger.info "Roles for #{instance_alias} are now:"
      logger.info instance.role_names.sort.join("\n")
    end
  end
  
  # The :add_role and :remove_role tasks are for backwards-compatibility
  desc <<-DESC
    Alias for rubber:roles:add
  DESC
  required_task :add_role do
    rubber.roles.add()
  end

  desc <<-DESC
    Alias for rubber:roles:remove
  DESC
  required_task :remove_role do
    rubber.roles.remove()
  end

  desc <<-DESC
    List all your EC2 instances
  DESC
  required_task :describe do
    results = []
    format = "%-10s %-10s %-10s %-10s %-15s %-30s"
    results << format % %w[InstanceID Type State Zone IP Alias\ (*=unknown)]

    instances = cloud.describe_instances()
    data = []
    instances.each do |instance|
      local_alias = find_alias(instance[:external_ip], instance[:id], instance[:state] == 'running')
      data << [instance[:id], instance[:type], instance[:state], instance[:zone], instance[:external_ip] || "NoIP", local_alias || "Unknown"]
    end

    # sort by alias
    data = data.sort {|r1, r2| r1.last <=> r2.last }
    results.concat(data.collect {|r| format % r})

    results.each {|r| logger.info(r) }
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
        roles = env.instance_roles.split(/\s*,\s*/) rescue []
      end

      # If user doesn't setup a primary db, then be nice and do it
      if ! roles.include?("db:primary=true") && rubber_instances.for_role("db").size == 0
        value = Capistrano::CLI.ui.ask("You do not have a primary db role, should #{instance_alias} be it [y/n]?: ")
        roles << "db:primary=true" if value =~ /^y/
      end

      ir.concat roles.collect {|r| Rubber::Configuration::RoleItem.parse(r) }

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

  set :monitor, Monitor.new

  # Creates a new ec2 instance with the given alias and roles
  # Configures aliases (/etc/hosts) on local and remote machines
  def create_instance(instance_alias, instance_roles, create_spot_instance)
    role_names = instance_roles.collect{|x| x.name}
    env = rubber_cfg.environment.bind(role_names, instance_alias)

    monitor.synchronize do
      cloud.before_create_instance(instance_alias, role_names)
    end

    security_groups = get_assigned_security_groups(instance_alias, role_names)

    cloud_env = env.cloud_providers[env.cloud_provider]
    ami = cloud_env.image_id
    ami_type = cloud_env.image_type
    availability_zone = cloud_env.availability_zone
    region = cloud_env.region

    create_spot_instance ||= cloud_env.spot_instance

    if create_spot_instance
      spot_price = cloud_env.spot_price.to_s

      logger.info "Creating spot instance request for instance #{ami}/#{ami_type}/#{security_groups.join(',') rescue 'Default'}/#{availability_zone || 'Default'}"
      request_id = cloud.create_spot_instance_request(spot_price, ami, ami_type, security_groups, availability_zone)

      print "Waiting for spot instance request to be fulfilled"
      max_wait_time = cloud_env.spot_instance_request_timeout || (1.0 / 0) # Use the specified timeout value or default to infinite.
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
      logger.info "Creating instance #{ami}/#{ami_type}/#{security_groups.join(',') rescue 'Default'}/#{availability_zone || region || 'Default'}"
      instance_id = cloud.create_instance(instance_alias, ami, ami_type, security_groups, availability_zone, region)
    end

    logger.info "Instance #{instance_alias} created: #{instance_id}"

    instance_item = Rubber::Configuration::InstanceItem.new(instance_alias, env.domain, instance_roles, instance_id, ami_type, ami, security_groups)
    instance_item.spot_instance_request_id = request_id if create_spot_instance
    rubber_instances.add(instance_item)
    rubber_instances.save()

    monitor.synchronize do
      cloud.after_create_instance(instance_item)
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

    instance = cloud.describe_instances(instance_item.instance_id).first

    monitor.synchronize do
      cloud.before_refresh_instance(instance_item)
    end

    if instance[:state] == cloud.active_state
      print "\n"
      logger.info "Instance running, fetching hostname/ip data"
      instance_item.external_host = instance[:external_host]
      instance_item.external_ip = instance[:external_ip]
      instance_item.internal_host = instance[:internal_host]
      instance_item.internal_ip = instance[:internal_ip]
      instance_item.zone = instance[:zone]
      instance_item.provider = instance[:provider]
      instance_item.platform = instance[:platform]
      instance_item.root_device_type = instance[:root_device_type]
      rubber_instances.save()

      if instance_item.linux?
        # weird cap/netssh bug, sometimes just hangs forever on initial connect, so force a timeout
        begin
          Timeout::timeout(30) do
            puts 'Trying to enable root login'

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

      monitor.synchronize do
        cloud.after_refresh_instance(instance_item)
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

    value = Capistrano::CLI.ui.ask("About to DESTROY #{instance_alias} (#{instance_item.instance_id}) in mode #{Rubber.env}.  Are you SURE [yes/NO]?: ") unless force
    fatal("Exiting", 0) if value != "yes" && ! force

    if instance_item.static_ip
      value = Capistrano::CLI.ui.ask("Instance has a static ip, do you want to release it? [y/N]?: ") unless force
      destroy_static_ip(instance_item.static_ip) if value =~ /^y/ || force
    end

    if instance_item.volumes
      value = Capistrano::CLI.ui.ask("Instance has persistent volumes, do you want to destroy them? [y/N]?: ") unless force || cloud.should_destroy_volume_when_instance_destroyed?
      if value =~ /^y/ || force || cloud.should_destroy_volume_when_instance_destroyed?
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
  
  def reboot_instances(instance_aliases, force=false)
    instance_aliases.each do |instance_alias|
      reboot_instance(instance_alias, force)
    end
  end
  
  # Reboots the given ec2 instance
  def reboot_instance(instance_alias, force=false)
    instance_item = rubber_instances[instance_alias]
    fatal "Instance does not exist: #{instance_alias}" if ! instance_item

    env = rubber_cfg.environment.bind(instance_item.role_names, instance_item.name)

    value = Capistrano::CLI.ui.ask("About to REBOOT #{instance_alias} (#{instance_item.instance_id}) in mode #{Rubber.env}.  Are you SURE [yes/NO]?: ") unless force
    fatal("Exiting", 0) if value != "yes" && ! force

    logger.info "Rebooting instance alias=#{instance_alias}, instance_id=#{instance_item.instance_id}"

    cloud.reboot_instance(instance_item.instance_id)
  end
  
  # Stops the given ec2 instances.  Note that this operation only works for instances that use an EBS volume for the root
  # device and that are not spot instances.
  def stop_instances(aliases)
    stop_threads = []
    
    instance_items = aliases.collect{|instance_alias| rubber_instances[instance_alias]}
    instance_items = aliases.collect do |instance_alias|
      instance_item = rubber_instances[instance_alias]
      
      fatal "Instance does not exist: #{instance_alias}" if ! instance_item
      
      instance_item
    end

    monitor.synchronize do
      instance_items.each do |instance_item|
        cloud.before_stop_instance(instance_item)
      end
    end
    
    # Get user confirmation
    human_instance_list = instance_items.collect{|instance_item| "#{instance_item.name} (#{instance_item.instance_id})"}.join(', ')
    value = Capistrano::CLI.ui.ask("About to STOP #{human_instance_list} in mode #{Rubber.env}.  Are you SURE [yes/NO]?: ")
    fatal("Exiting", 0) if value != "yes"
    
    instance_items.each do |instance_item|
      logger.info "Stopping instance alias=#{instance_item.name}, instance_id=#{instance_item.instance_id}"
      
      stop_threads << Thread.new do
        env = rubber_cfg.environment.bind(instance_item.role_names, instance_item.name)

        cloud.stop_instance(instance_item)
        
        stopped = false
        while !stopped
          sleep 1
          instance = cloud.describe_instances(instance_item.instance_id).first rescue {}
          stopped = (instance[:state] == cloud.stopped_state)
        end
      end
    end
      
    print "Waiting for #{instance_items.size == 1 ? 'instance' : 'instances'} to stop"
    while true do
      print "."
      sleep 2
      break unless stop_threads.any?(&:alive?)
    end
    print "\n"
      
    stop_threads.each(&:join)

    monitor.synchronize do
      instance_items.each do |instance_item|
        cloud.after_stop_instance(instance_item)
      end
    end
  end

  # Starts the given ec2 instances.  Note that this operation only works for instances that use an EBS volume for the root
  # device, that are not spot instances, and that are already stopped.
  def start_instances(aliases)
    start_threads = []
    describe_threads = []
    
    instance_items = aliases.collect do |instance_alias|
      instance_item = rubber_instances[instance_alias]

      fatal "Instance does not exist: #{instance_alias}" if ! instance_item

      instance_item
    end

    monitor.synchronize do
      instance_items.each do |instance_item|
        cloud.before_start_instance(instance_item)
      end
    end
    
    # Get user confirmation
    human_instance_list = instance_items.collect{|instance_item| "#{instance_item.name} (#{instance_item.instance_id})"}.join(', ')
    value = Capistrano::CLI.ui.ask("About to START #{human_instance_list} in mode #{Rubber.env}.  Are you SURE [yes/NO]?: ")
    fatal("Exiting", 0) if value != "yes"
  
    instance_items.each do |instance_item|
      logger.info "Starting instance alias=#{instance_item.name}, instance_id=#{instance_item.instance_id}"
      
      start_threads << Thread.new do
        env = rubber_cfg.environment.bind(instance_item.role_names, instance_item.name)
        
        cloud.start_instance(instance_item)

        describe_threads << Thread.new do
          started = false
          while ! started
            sleep 1
            instance = cloud.describe_instances(instance_item.instance_id).first rescue {}
            started = (instance[:state] == cloud.active_state)
          end
        end
      end
    end
    
    print "Waiting for #{instance_items.size == 1 ? 'instance' : 'instances'} to start"
    while true do
      print "."
      sleep 2
      break unless start_threads.any?(&:alive?)
    end

    start_threads.each(&:join)
    describe_threads.each(&:join)

    monitor.synchronize do
      instance_items.each do |instance_item|
        cloud.after_start_instance(instance_item)
      end
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
