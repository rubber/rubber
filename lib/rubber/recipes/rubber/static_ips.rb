namespace :rubber do


  desc <<-DESC
    Sets up static IPs for the instances configured to have them
  DESC
  required_task :setup_static_ips do
    rubber_instances.each do |ic|
      env = rubber_cfg.environment.bind(ic.role_names, ic.name)
      if env.use_static_ip
        artifacts = rubber_instances.artifacts
        ip = artifacts['static_ips'][ic.name] rescue nil

        # first allocate the static ip if we don't have a global record (artifacts) for it
        if ! ip
          logger.info "Allocating static IP for #{ic.full_name}"
          ip = allocate_static_ip()
          artifacts['static_ips'][ic.name] = ip
          rubber_instances.save
        end

        # then, associate it if we don't have a record (on instance) of association or it
        # doesn't match the instance's current external ip
        if !ic.static_ip || ip != ic.external_ip
          logger.info "Associating static ip #{ip} with #{ic.full_name}"
          associate_static_ip(ip, ic.instance_id)

          instance = cloud.describe_instances(ic.instance_id).first
          ic.external_host = instance[:external_host]
          ic.internal_host = instance[:internal_host]
          ic.external_ip = ip
          ic.static_ip = ip
          rubber_instances.save()

          logger.info "Waiting for static ip to associate"
          while true do
            task :_wait_for_static_ip, :hosts => ip do
              run "echo"
            end
            begin
              _wait_for_static_ip
            rescue ConnectionError
              sleep 2
              logger.info "Failed to connect to static ip #{ip}, retrying"
              retry
            end
            break
          end
        end

      end
    end
  end

  desc <<-DESC
    Shows the configured static IPs
  DESC
  required_task :describe_static_ips do
    results = []
    format = "%-10s %-15s %-30s"
    results << format % %w[InstanceID IP Alias]

    ips = cloud.describe_static_ips()
    ips.each do |ip_data|
      instance_id = ip_data[:instance_id]
      ip = ip_data[:ip]

      local_alias = find_alias(ip, instance_id, false)

      results << format % [instance_id || "Unassigned", ip, local_alias || "Unknown"]
    end
    
    results.each {|r| logger.info r}
  end

  desc <<-DESC
    Deallocates the given static ip
  DESC
  required_task :destroy_static_ip do
    ip = get_env('IP', "Static IP (run rubber:describe_static_ips for a list)", true)
    destroy_static_ip(ip)
  end

  desc 'Move a static IP address from DONOR machine to RECEIVER machine.'
  task :move_static_ip do
    donor_alias = get_env 'DONOR', 'Instance alias to get the IP from (e.g., web01)', true
    receiver_alias = get_env 'RECEIVER', 'Instance alias to assign the IP to (e.g., web02)', true

    # Sanity checks
    donor = rubber_instances[donor_alias]
    fatal "Instance does not exist: #{donor_alias}" unless donor

    static_ip = donor.static_ip
    fatal 'No static IP address to move exists' unless static_ip && static_ip != ''

    receiver = rubber_instances[receiver_alias]
    fatal "Instance does not exist: #{receiver_alias}" unless receiver

    # Temporary removal of the instances.
    old_donor = rubber_instances.remove(donor_alias)
    old_receiver = rubber_instances.remove(receiver_alias)

    rubber_instances.save

    # Getting rid of alias->IP mappings and SSH's known_hosts records.
    load_roles
    setup_aliases
    cleanup_known_hosts(old_donor)
    cleanup_known_hosts(old_receiver)

    # Detachment of EIPA.
    success = cloud.detach_static_ip(static_ip)
    fatal "Failed to detach static IP address #{static_ip}" unless success
    rubber_instances.artifacts['static_ips'].delete(old_donor.name)

    rubber_instances.save

    # Attachment of EIPA.
    success = cloud.attach_static_ip(static_ip, old_receiver.instance_id)
    fatal "Failed to associate static IP address #{static_ip}" unless success

    print "Waiting for #{receiver_alias} to get the address"
    while true do
      print '.'
      sleep 3
      instance = cloud.describe_instances(old_receiver.instance_id).first
      break if instance[:external_ip] == static_ip
    end

    # Partial cleanup of static IP records.
    rubber_instances.artifacts['static_ips'][old_receiver.name] = static_ip

    rubber_instances.save

    # First half of the sync.
    new_receiver = Rubber::Configuration::InstanceItem.new(old_receiver.name,
      old_receiver.domain, old_receiver.roles, old_receiver.instance_id,
      old_receiver.image_type, old_receiver.image_id,
      old_receiver.security_groups)
    new_receiver.static_ip = static_ip
    rubber_instances.add(new_receiver)

    rubber_instances.save

    refresh_instance(receiver_alias)

    print "Waiting for #{donor_alias} to get a new address"
    while true do
      print '.'
      sleep 3
      instance = cloud.describe_instances(old_donor.instance_id).first
      break if instance[:external_ip] && instance[:external_ip] != ''
    end

    # Second half of the sync.
    new_donor = Rubber::Configuration::InstanceItem.new(old_donor.name,
      old_donor.domain, old_donor.roles, old_donor.instance_id,
      old_donor.image_type, old_donor.image_id,
      old_donor.security_groups)
    rubber_instances.add(new_donor)

    rubber_instances.save

    refresh_instance(donor_alias)

    logger.info "Run 'cap rubber:describe_static_ips' to check the allocated ones"
  end

  def allocate_static_ip()
    ip = cloud.create_static_ip()
    fatal "Failed to allocate static ip" if ip.nil?
    return ip
  end

  def associate_static_ip(ip, instance_id)
    success = cloud.attach_static_ip(ip, instance_id)
    fatal "Failed to associate static ip" unless success
  end

  def destroy_static_ip(ip)
    logger.info "Releasing static ip: #{ip}"
    cloud.destroy_static_ip(ip) rescue logger.info("IP was not attached")

    logger.info "Removing ip #{ip} from rubber instances file"
    artifacts = rubber_instances.artifacts
    artifacts['static_ips'].delete_if {|k,v| v == ip}
    rubber_instances.each do |ic|
      ic.static_ip = nil if ic.static_ip == ip
    end
    rubber_instances.save
  end

end
