namespace :rubber do


  desc <<-DESC
    Sets up static IPs for the instances configured to have them
  DESC
  required_task :setup_static_ips do
    rubber_cfg.instance.each do |ic|
      env = rubber_cfg.environment.bind(ic.role_names, ic.name)
      if env.use_static_ip
        artifacts = rubber_cfg.instance.artifacts
        ip = artifacts['static_ips'][ic.name] rescue nil

        # first allocate the static ip if we don't have a global record (artifacts) for it
        if ! ip
          logger.info "Allocating static IP for #{ic.full_name}"
          ip = allocate_static_ip()
          artifacts['static_ips'][ic.name] = ip
          rubber_cfg.instance.save
        end

        # then, associate it if we don't have a record (on instance) of association
        if ! ic.static_ip
          logger.info "Associating static ip #{ip} with #{ic.full_name}"
          associate_static_ip(ip, ic.instance_id)

          instance = cloud.describe_instances(:instance_id => ic.instance_id).first
          ic.external_host = instance[:external_host]
          ic.internal_host = instance[:internal_host]
          ic.external_ip = ip
          ic.static_ip = ip
          rubber_cfg.instance.save()

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
    artifacts = rubber_cfg.instance.artifacts
    artifacts['static_ips'].delete_if {|k,v| v == ip}
    rubber_cfg.instance.each do |ic|
      ic.static_ip = nil if ic.static_ip == ip
    end
    rubber_cfg.instance.save
  end

end
