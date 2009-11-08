namespace :rubber do

  desc <<-DESC
    Create a new EC2 instance with the given ALIAS and ROLES
  DESC
  required_task :create do
    instance_alias = get_env('ALIAS', "Instance alias (e.g. web01)", true)

    env = rubber_cfg.environment.bind(nil, instance_alias)
    default_roles = env.instance_roles
    r = get_env("ROLES", "Instance roles (e.g. web,app,db:primary=true)", true, default_roles)

    if r == '*'
      instance_roles = rubber_cfg.environment.known_roles
      instance_roles = instance_roles.collect {|role| role == "db" ? "db:primary=true" : role }
    else
      instance_roles = r.split(",")
    end

    ir = []
    instance_roles.each do |r|
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

    create_instance(instance_alias, ir)
  end

  desc <<-DESC
    Refresh the host data for a EC2 instance with the given ALIAS.
    This is useful to run when rubber:create fails after instance creation
  DESC
  task :refresh do
    instance_alias = get_env('ALIAS', "Instance alias (e.g. web01)", true)
    ENV.delete('ROLES') # so we don't get an error if people leave ROLES in env from :create CLI
    refresh_instance(instance_alias)
  end

  desc <<-DESC
    Destroy the EC2 instance for the given ALIAS
  DESC
  task :destroy do
    instance_alias = get_env('ALIAS', "Instance alias (e.g. web01)", true)
    ENV.delete('ROLES') # so we don't get an error if people leave ROLES in env from :create CLI
    destroy_instance(instance_alias)
  end

  desc <<-DESC
    Destroy ALL the EC2 instances for the current env
  DESC
  task :destroy_all do
    rubber_instances.each do |ic|
      destroy_instance(ic.name)
    end
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

  # Creates a new ec2 instance with the given alias and roles
  # Configures aliases (/etc/hosts) on local and remote machines
  def create_instance(instance_alias, instance_roles)
    fatal "Instance already exists: #{instance_alias}" if rubber_instances[instance_alias]

    role_names = instance_roles.collect{|x| x.name}
    env = rubber_cfg.environment.bind(role_names, instance_alias)

    # We need to use security_groups during create, so create them up front
    setup_security_groups(instance_alias, role_names)
    security_groups = get_assigned_security_groups(instance_alias, role_names)

    ami = env.cloud_providers[env.cloud_provider].image_id
    ami_type = env.cloud_providers[env.cloud_provider].image_type
    availability_zone = env.availability_zone
    logger.info "Creating instance #{ami}/#{ami_type}/#{security_groups.join(',') rescue 'Default'}/#{availability_zone || 'Default'}"
    instance_id = cloud.create_instance(ami, ami_type, security_groups, availability_zone)

    logger.info "Instance #{instance_id} created"

    instance_item = Rubber::Configuration::InstanceItem.new(instance_alias, env.domain, instance_roles, instance_id, security_groups)
    rubber_instances.add(instance_item)
    rubber_instances.save()


    print "Waiting for instance to start"
    while true do
      print "."
      sleep 2
      instance = cloud.describe_instances(instance_id).first

      if instance[:state] == "running"
        print "\n"
        logger.info "Instance running, fetching hostname/ip data"
        instance_item.external_host = instance[:external_host]
        instance_item.external_ip = instance[:external_ip]
        instance_item.internal_host = instance[:internal_host]
        instance_item.zone = instance[:zone]
        rubber_instances.save()

        # setup amazon elastic ips if configured to do so
        setup_static_ips

        # Need to setup aliases so ssh doesn't give us errors when we
        # later try? to connect to same ip but using alias
        setup_local_aliases

        # re-load the roles since we may have just defined new ones
        load_roles() unless env.disable_auto_roles

        # Connect to newly created instance and grab its internal ip
        # so that we can update all aliases

        task :_get_ip, :hosts => instance_item.external_ip do
          instance_item.internal_ip = capture(print_ip_command).strip
          rubber_instances.save()
        end

        # even though instance is running, sometimes ssh hasn't started yet,
        # so retry on connect failure
        begin
          _get_ip
        rescue ConnectionError
          sleep 2
          logger.info "Failed to connect to #{instance_alias} (#{instance_item.external_ip}), retrying"
          retry
        end

        # Add the aliases for this instance to all other hosts
        setup_remote_aliases
        setup_dns_aliases

        break
      end
    end
  end

  # Refreshes a ec2 instance with the given alias
  # Configures aliases (/etc/hosts) on local and remote machines
  def refresh_instance(instance_alias)
    instance_item = rubber_instances[instance_alias]

    fatal "Instance does not exist: #{instance_alias}" if ! instance_item

    env = rubber_cfg.environment.bind(instance_item.role_names, instance_alias)
    
    instance = cloud.describe_instances(instance_item.instance_id).first

    if instance[:state] == "running"
      logger.info "\nInstance running, fetching hostname/ip data"
      instance_item.external_host = instance[:external_host]
      instance_item.external_ip = instance[:external_ip]
      instance_item.internal_host = instance[:internal_host]
      instance_item.zone = instance[:zone]

      # setup amazon elastic ips if configured to do so
      setup_static_ips
      
      # Need to setup aliases so ssh doesn't give us errors when we
      # later try to connect to same ip but using alias
      setup_local_aliases

      # re-load the roles since we may have just defined new ones
      load_roles() unless env.disable_auto_roles

      # Connect to newly created instance and grab its internal ip
      # so that we can update all aliases
      task :_get_ip, :hosts => instance_item.external_ip do
        instance_item.internal_ip = capture(print_ip_command).strip
        rubber_instances.save()
      end

      # even though instance is running, sometimes ssh hasn't started yet,
      # so retry on connect failure
      begin
        _get_ip
      rescue ConnectionError
        sleep 2
        logger.info "Failed to connect to #{instance_alias} (#{instance_item.external_ip}), retrying"
        retry
      end


      # Add the aliases for this instance to all other hosts
      setup_remote_aliases
      setup_dns_aliases
    end
  end


  # Destroys the given ec2 instance
  def destroy_instance(instance_alias)
    instance_item = rubber_instances[instance_alias]
    fatal "Instance does not exist: #{instance_alias}" if ! instance_item

    env = rubber_cfg.environment.bind(instance_item.role_names, instance_item.name)

    value = Capistrano::CLI.ui.ask("About to DESTROY #{instance_alias} (#{instance_item.instance_id}) in mode #{RUBBER_ENV}.  Are you SURE [yes/NO]?: ")
    fatal("Exiting", 0) if value != "yes"

    if instance_item.static_ip
      value = Capistrano::CLI.ui.ask("Instance has a static ip, do you want to release it? [y/N]?: ")
      destroy_static_ip(instance_item.static_ip) if value =~ /^y/
    end

    if instance_item.volumes
      value = Capistrano::CLI.ui.ask("Instance has persistent volumes, do you want to destroy them? [y/N]?: ")
      if value =~ /^y/
        instance_item.volumes.clone.each do |volume_id|
          destroy_volume(volume_id)
        end
      end
    end

    logger.info "Destroying instance alias=#{instance_alias}, instance_id=#{instance_item.instance_id}"

    cloud.destroy_instance(instance_item.instance_id)

    rubber_instances.remove(instance_alias)
    rubber_instances.save()

    # re-load the roles since we just removed some and setup_remote_aliases
    # shouldn't hit removed ones
    load_roles() unless env.disable_auto_roles

    setup_aliases
    destroy_dyndns(instance_item)
    cleanup_known_hosts(instance_item) unless env.disable_known_hosts_cleanup
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
