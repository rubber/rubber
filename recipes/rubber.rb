# add this plugins lib dir to load path for capistrano
$:.unshift "#{File.dirname(__FILE__)}/../lib"

require "socket"
require 'resolv'
require 'enumerator'
require 'rubber/util'
require 'rubber/configuration'
require 'capistrano/hostcmd'
require 'pp'

require 'rubygems'
require 'EC2'

namespace :rubber do

  # advise capistrano's task method so that tasks for non-existant roles don't
  # fail when roles isn't defined due to using a FILTER for load_roles
  # If you have a task you need to execute even when there are no
  # roles, you have to use required_task instead of task - see rubber:create
  # as an example of this role bootstrapping problem.
  def allow_optional_tasks(ns)
    class << ns
      alias :required_task :task
      def task(name, options={}, &block)
        required_task(name, options) do
          # define empty roles for the case when a task has a role that we don't define anywhere
          [*options[:roles]].each do |r|
            roles[r] ||= []
          end
          
          if find_servers_for_task(current_task).empty?
            logger.info "No servers for task #{name}, skipping"
            next
          end
          block.call
        end
      end
    end
  end
  
  allow_optional_tasks(self)
  on :load, "rubber:init"
    

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

  required_task :init do
    # pull in basic rails env.  rubber only needs RAILS_ROOT and RAILS_ENV.
    # We actually do NOT want the entire rails environment because it
    # complicates bootstrap (i.e. can't run config to create db because full
    # rails env needs db to exist as some plugin accesses model or something)
    if ! defined?(RAILS_ROOT)
      if File.dirname(__FILE__) =~ /vendor\/plugins/
        require(File.join(File.dirname(__FILE__), '../../../../config/boot'))
      else
        fatal "Cannot load rails env because rubber is not being used as a rails plugin"
      end
    end
    
    # Require cap 2.4 since we depend on bugs that have been fixed
    require 'capistrano/version'
    if Capistrano::Version::MAJOR < 2 || Capistrano::Version::MINOR < 4
      fatal "rubber requires capistrano 2.4.0 or greater"
    end
    
    set :rubber_cfg, Rubber::Configuration.get_configuration(ENV['RAILS_ENV'])
    load_roles() unless rubber_cfg.environment.bind().disable_auto_roles
    # NOTE: for some reason Capistrano requires you to have both the public and
    # the private key in the same folder, the public key should have the
    # extension ".pub".
    ssh_options[:keys] = rubber_cfg.environment.bind().ec2_key_file
  end

  desc <<-DESC
    Create a new EC2 instance with the given ALIAS and ROLES
  DESC
  required_task :create do
    instance_alias = get_env('ALIAS', "Instance alias (e.g. web01)", true)
    r = get_env('ROLES', "Instance roles (e.g. web,app,db:primary=true)", true)
    if r == '*'
      instance_roles = rubber_cfg.environment.known_roles
      instance_roles = instance_roles.collect {|role| role == "db" ? "db:primary=true" : role }
    else
      instance_roles = r.split(",")
    end
    
    ir = []
    instance_roles.each do |r|
      data = r.split(':');
      role = Rubber::Configuration::RoleItem.new(data[0])
      if data[1]
        data[1].split(';').each do |pair|
          p = pair.split('=')
          val = case p[1]
                  when 'true' then true
                  when 'false' then false
                  else p[1] end
          role.options[p[0]] = val
        end
      end

      # If user doesn't setup a primary db, then be nice and do it
      if role.name == "db" && role.options["primary"] == nil && rubber_cfg.instance.for_role("db").size == 0
        value = Capistrano::CLI.ui.ask("You do not have a primary db role, should #{instance_alias} be it [y/n]?: ")
        role.options["primary"] = true if value =~ /^y/
      end

      ir << role
    end

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
    rubber_cfg.instance.each do |ic|
      destroy_instance(ic.name)
    end
  end

  desc <<-DESC
    List all your EC2 instances
  DESC
  required_task :describe do
    env = rubber_cfg.environment.bind()
    ec2 = EC2::Base.new(:access_key_id => env.aws_access_key, :secret_access_key => env.aws_secret_access_key)
    
    results = []
    format = "%-10s %-10s %-10s %-15s %-30s"
    results << format % %w[InstanceID State Zone IP Alias\ (*=unknown)]
    
    response = ec2.describe_instances()
    response.reservationSet.item.each do |ritem|
      ritem.instancesSet.item.each do |item|
        ip = IPSocket.getaddress(item.dnsName) rescue nil
        instance_id = item.instanceId
        state = item.instanceState.name
        local_alias = find_alias(ip, instance_id, state == 'running')
        zone = item.placement.availabilityZone
        results << format % [instance_id, state, zone, ip || "NoIP", local_alias || "Unknown"]
      end
    end if response.reservationSet
    results.each {|r| logger.info r}
  end

  desc <<-DESC
    Bootstraps instances by setting timezone, installing packages and gems
  DESC
  task :bootstrap do
    set_timezone
    link_bash
    install_packages
    add_gem_sources
    install_gems
  end

  desc <<-DESC
    Sets up aliases for instance hostnames based on contents of instance.yml.
    Generates /etc/hosts for local/remote machines and sets hostname on
    remote instances, and sets values in dynamic dns entries
  DESC
  required_task :setup_aliases do
    setup_local_aliases
    setup_remote_aliases
    setup_dns_aliases
  end

  desc <<-DESC
    Sets up local aliases for instance hostnames based on contents of instance.yml.
    Generates/etc/hosts for local machine
  DESC
  required_task :setup_local_aliases do
    hosts_file = '/etc/hosts'

    # Generate /etc/hosts contents for the local machine from instance config
    env = rubber_cfg.environment.bind()
    delim = "## rubber config #{env.domain} #{ENV['RAILS_ENV']}"
    local_hosts = delim + "\n"
    rubber_cfg.instance.each do |ic|
      # don't add unqualified hostname in local hosts file since user may be
      # managing multiple domains with same aliases
      hosts_data = [ic.full_name, ic.external_host, ic.internal_host].join(' ')
      local_hosts << ic.external_ip << ' ' << hosts_data << "\n"
    end
    local_hosts << delim << "\n"

    # Write out the hosts file for this machine, use sudo
    filtered = File.read(hosts_file).gsub(/^#{delim}.*^#{delim}\n?/m, '')
    logger.info "Writing out aliases into local machines #{hosts_file}, sudo access needed"
    Rubber::Util::sudo_open(hosts_file, 'w') do |f|
      f.write(filtered)
      f.write(local_hosts)
    end
  end

  desc <<-DESC
    Sets up aliases in dynamic dns provider for instance hostnames based on contents of instance.yml.
  DESC
  required_task :setup_dns_aliases do
    rubber_cfg.instance.each do |ic|
      update_dyndns(ic)
    end
  end

  desc <<-DESC
    Sets up aliases for instance hostnames based on contents of instance.yml.
    Generates /etc/hosts for remote machines and sets hostname on remote instances
  DESC
  task :setup_remote_aliases do
    hosts_file = '/etc/hosts'

    # Generate /etc/hosts contents for the remote( ec2) instance from instance config
    delim = "## rubber config"
    delim = "#{delim} #{ENV['RAILS_ENV']}" if ENV['RAILS_ENV']
    remote_hosts = delim + "\n"
    rubber_cfg.instance.each do |ic|
      hosts_data = [ic.name, ic.full_name, ic.external_host, ic.internal_host].join(' ')
      remote_hosts << ic.internal_ip << ' ' << hosts_data << "\n"
    end
    remote_hosts << delim << "\n"
    if rubber_cfg.instance.size > 0
      # write out the hosts file for the remote instances
      # NOTE that we use "capture" to get the existing hosts
      # file, which only grabs the hosts file from the first host
      filtered = (capture "cat #{hosts_file}").gsub(/^#{delim}.*^#{delim}\n?/m, '')
      filtered = filtered + remote_hosts
      # Put the generated hosts back on remote instance
      put filtered, hosts_file

      # Setup hostname on instance so shell, etcs have nice display
      sudo "echo $CAPISTRANO:HOST$ > /etc/hostname && hostname $CAPISTRANO:HOST$"
    end

    # TODO
    # /etc/resolv.conf to add search domain
    # ~/.ssh/options to setup user/host/key aliases
  end
  

  def inject_auto_security_groups(groups, hosts, roles)
    hosts.each do |name|
      group_name = name
      groups[group_name] ||= {'description' => "Rubber automatic security group for host: #{name}", 'rules' => []}
    end
    roles.each do |name|
      group_name = name
      groups[group_name] ||= {'description' => "Rubber automatic security group for role: #{name}", 'rules' => []}
    end
    return groups
  end

  def sync_security_groups(groups)
    env = rubber_cfg.environment.bind()
    return unless groups
    
    groups = Rubber::Util::stringify(groups)
    group_keys = groups.keys.clone()
    ec2 = EC2::Base.new(:access_key_id => env.aws_access_key, :secret_access_key => env.aws_secret_access_key)
    
    # For each group that does already exist in ec2
    response = ec2.describe_security_groups()
    response.securityGroupInfo.item.each do |item|
      if group_keys.delete(item.groupName)
        # sync rules
        logger.debug "Security Group already in ec2, syncing rules: #{item.groupName}"
        group = groups[item.groupName]
        rules = group['rules'].clone
        rule_maps = []
        
        # first collect the rule maps from the request (group/user pairs are duplicated for tcp/udp/icmp, 
        # so we need to do this up frnot and remove duplicates before checking against the local rubber rules)
        item.ipPermissions.item.each do |rule|
          if rule.groups
            rule.groups.item.each do |rule_group|
              rule_map = {'source_security_group_name' => rule_group.groupName, 'source_security_group_owner_id' => rule_group.userId}
              rule_map = Rubber::Util::stringify(rule_map)
              rule_maps << rule_map unless rule_maps.include?(rule_map)
            end
          else
            rule_map = {'ip_protocol' => rule.ipProtocol, 'from_port' => rule.fromPort.to_i, 'to_port' => rule.toPort.to_i}
            rule.ipRanges.item.each do |ip|
              rule_map = rule_map.merge('cidr_ip' => ip.cidrIp)
              rule_map = Rubber::Util::stringify(rule_map)
              rule_maps << rule_map unless rule_maps.include?(rule_map)
            end if rule.ipRanges
          end
        end if item.ipPermissions
        
        # For each rule, if it exists, do nothing, otherwise remove it as its no longer defined locally
        rule_maps.each do |rule_map|
          if rules.delete(rule_map)
            # rules match, don't need to do anything
            # logger.debug "Rule in sync: #{rule_map.inspect}"
          else
            # rules don't match, remove them from ec2 and re-add below
            answer = Capistrano::CLI.ui.ask("Rule '#{rule_map.inspect}' exists in ec2, but not locally, remove from ec2? [y/N]?: ")
            rule = Rubber::Util::symbolize_keys(rule_map.merge(:group_name => item.groupName))
            ec2.revoke_security_group_ingress(rule) if answer =~ /^y/
          end
        end
        
        rules.each do |rule|
          # create non-existing rules
          logger.debug "Missing rule, creating: #{rule.inspect}"
          rule = Rubber::Util::symbolize_keys(rule.merge(:group_name => item.groupName))
          ec2.authorize_security_group_ingress(rule)
        end
      else
        # when using auto groups, get prompted too much to delete when
        # switching between production/staging since the hosts aren't shared
        # between the two environments
        if env.force_security_group_cleanup || ! env.auto_security_groups
          # delete group
          answer = Capistrano::CLI.ui.ask("Security group '#{item.groupName}' exists in ec2 but not locally, remove from ec2? [y/N]: ")
          ec2.delete_security_group(:group_name => item.groupName) if answer =~ /^y/
        end
      end
    end
    
    # For each group that didnt already exist in ec2
    group_keys.each do |key|
      group = groups[key]
      logger.debug "Creating new security group: #{key}"
      # create each group
      ec2.create_security_group(:group_name => key, :group_description => group['description'])
      # create rules for group
      group['rules'].each do |rule|
        logger.debug "Creating new rule: #{rule.inspect}"
        rule = Rubber::Util::symbolize_keys(rule.merge(:group_name => key))
        ec2.authorize_security_group_ingress(rule)
      end
    end
  end
    
  desc <<-DESC
    Sets up the network security groups
    All defined groups will be created, and any not defined will be removed.
    Likewise, rules within a group will get created, and those not will be removed
  DESC
  required_task :setup_security_groups do
    env = rubber_cfg.environment.bind()
    security_group_defns = env.ec2_security_groups
    if env.auto_security_groups
      hosts = rubber_cfg.instance.collect{|ic| ic.name }
      roles = rubber_cfg.instance.all_roles
      security_group_defns = inject_auto_security_groups(security_group_defns, hosts, roles)
      sync_security_groups(security_group_defns)
    else
      sync_security_groups(security_group_defns)
    end
  end

  desc <<-DESC
    Describes the network security groups
  DESC
  required_task :describe_security_groups do
    env = rubber_cfg.environment.bind()
    ec2 = EC2::Base.new(:access_key_id => env.aws_access_key, :secret_access_key => env.aws_secret_access_key)
    
    response = ec2.describe_security_groups()
    puts response.securityGroupInfo.item.pretty_inspect
  end

  desc <<-DESC
    Describes the availability zones
  DESC
  required_task :describe_zones do
    env = rubber_cfg.environment.bind()
    ec2 = EC2::Base.new(:access_key_id => env.aws_access_key, :secret_access_key => env.aws_secret_access_key)


    results = []
    format = "%-20s %-15s"
    results << format % %w[Name State]

    response = ec2.describe_availability_zones()
    response.availabilityZoneInfo.item.each do |item|
      results << format % [item.zoneName, item.zoneState]
    end if response.availabilityZoneInfo
    
    results.each {|r| logger.info r}
  end

  desc <<-DESC
    Sets up static IPs for the instances configured to have them
  DESC
  required_task :setup_static_ips do
    rubber_cfg.instance.each do |ic|
      env = rubber_cfg.environment.bind(ic.role_names, ic.name)
      if env.use_static_ip
        # I like to define the static ip I reservered before in rubber.yml
        if env.static_ip
          ic.static_ip = env.static_ip
          rubber_cfg.instance.save()
        end
        if ! ic.static_ip
          allocate_static_ip(ic)
        end
        if ic.static_ip && ic.static_ip != ic.external_ip
          associate_static_ip(ic)
        end
      end
    end
  end

  desc <<-DESC
    Assigns the given static ip to the given host
  DESC
  task :assign_static_ip do
    instance_alias = get_env('ALIAS', "Instance alias (e.g. web01)", true)
    instance_ip = get_env('IP', "Static IP (run rubber:describe_static_ips for a list)", true)
    
    ic = rubber_cfg.instance[instance_alias]
    env = rubber_cfg.environment.bind(ic.role_names, ic.name)
    
    fatal "#{instance_alias} is not configured to have a static_ip in rubber.yml" unless env.use_static_ip
    value = Capistrano::CLI.ui.ask("Static ip already assigned, #{instance_alias}:#{ic.static_ip}, proceed [y/n]?: ")
    fatal("Exiting", 0) if value !~ /^y/

    ic.static_ip = instance_ip
    associate_static_ip(ic)
  end

  desc <<-DESC
    Deallocates the given static ip
  DESC
  required_task :release_static_ip do
    instance_ip = get_env('IP', "Static IP (run rubber:describe_static_ips for a list)", true)
    deallocate_static_ip(instance_ip)    
  end

  desc <<-DESC
    Shows the configured static IPs
  DESC
  required_task :describe_static_ips do
    env = rubber_cfg.environment.bind()
    ec2 = EC2::Base.new(:access_key_id => env.aws_access_key, :secret_access_key => env.aws_secret_access_key)
    
    
    results = []
    format = "%-10s %-15s %-30s"
    results << format % %w[InstanceID IP Alias]
    
    response = ec2.describe_addresses()
    response.addressesSet.item.each do |item|
      instance_id = item.instanceId
      ip = item.publicIp
      
      local_alias = find_alias(ip, instance_id, false)
      
      results << format % [instance_id || "Unassigned", ip, local_alias || "Unknown"]
    end if response.addressesSet
    
    results.each {|r| logger.info r}
  end


  desc <<-DESC
    Update to the newest versions of all packages/gems.
  DESC
  task :update do
    upgrade_packages
    update_gems
  end

  desc <<-DESC
    Upgrade to the newest versions of all Ubuntu packages.
  DESC
  task :upgrade_packages do
    package_helper(true)
  end

  desc <<-DESC
    Upgrade to the newest versions of all rubygems.
  DESC
  task :update_gems do
    gem_helper(true)
  end

  desc <<-DESC
    Install extra packages and gems.
  DESC
  task :install do
    install_packages
    install_gems
  end

  desc <<-DESC
    Install extra Ubuntu packages. Set 'packages' in rubber.yml to \
    be an array of strings.
  DESC
  task :install_packages do
    package_helper(false)
  end

  desc <<-DESC
    Install extra ruby gems. Set 'gems' in rubber.yml to \
    be an array of strings.
  DESC
  task :install_gems do
    gem_helper(false)
  end

  desc <<-DESC
    Add extra ruby gems sources. Set 'gemsources' in rubber.yml to \
    be an array of URI strings.
  DESC
  task :add_gem_sources do
    env = rubber_cfg.environment.bind()
    if env.gemsources
      env.gemsources.each { |source| sudo "gem sources -a #{source}"}
    end
  end

  desc <<-DESC
    The ubuntu has /bin/sh linking to dash instead of bash, fix this
    You can override this task if you don't want this to happen
  DESC
  task :link_bash do
    sudo("ln -sf /bin/bash /bin/sh")
  end

  desc <<-DESC
    Set the timezone using the value of the variable named timezone. \
    Valid options for timezone can be determined by the contents of \
    /usr/share/zoneinfo, which can be seen here: \
    http://packages.ubuntu.com/cgi-bin/search_contents.pl?searchmode=filelist&word=tzdata&version=gutsy&arch=all&page=1&number=all \
    Remove 'usr/share/zoneinfo/' from the filename, and use the last \
    directory and file as the value. For example 'Africa/Abidjan' or \
    'posix/GMT' or 'Canada/Eastern'.
  DESC
  task :set_timezone do
    opts = get_host_options('timezone')
    sudo "bash -c 'echo $CAPISTRANO:VAR$ > /etc/timezone'", opts
    sudo "cp /usr/share/zoneinfo/$CAPISTRANO:VAR$ /etc/localtime", opts
    # restart syslog so that times match timezone
    sudo "/etc/init.d/sysklogd restart"
  end

  desc <<-DESC
    Configures the deployed rails application by running the rubber configuration process
  DESC
  task :config do
    opts = {}
    opts['NO_POST'] = true if ENV['NO_POST']
    opts['FILE'] = ENV['FILE'] if ENV['FILE']
    opts['RAILS_ENV'] = ENV['RAILS_ENV'] if ENV['RAILS_ENV']

    # when running deploy:migrations, we need to run config against release_path
    opts[:deploy_path] = current_release if fetch(:migrate_target, :current).to_sym == :latest
     
    run_config(opts)
  end

  set :mnt_vol, "/mnt"
    
  desc "Back up and register an image of the running instance to S3"
  task :bundle do
    if find_servers_for_task(current_task).size > 1
      fatal "Can only bundle a single instance at a time, use FILTER to limit the scope"
    end
    image_name = get_env('IMAGE', "The image name for the bundle", true, Time.now.strftime("%Y%m%d_%H%M"))
    bundle_vol(image_name)
    upload_bundle(image_name)
  end
  
  desc "De-register and Destroy the bundle for the given image name"
  required_task :destroy_bundle do
    ami = get_env('AMI', 'The AMI id of the image to be destroyed', true)
    delete_bundle(ami)
  end

  desc "Describes all your own registered bundles"
  required_task :describe_bundles do
    describe_bundles
  end

  desc <<-DESC
    Convenience task for creating a staging instance for the given RAILS_ENV.
    By default this task assigns all known roles when creating the instance,
    but you can specify a different default in rubber.yml:staging_roles
    At the end, the instance will be up and running
    e.g. RAILS_ENV=matt cap create_staging
  DESC
  required_task :create_staging do
    if rubber_cfg.instance.size > 0
      value = Capistrano::CLI.ui.ask("The #{rails_env} environment already has instances, Are you SURE you want to create a staging instance that may interact with them [y/N]?: ")
      fatal("Exiting", 0) if value !~ /^y/
    end
    ENV['ALIAS'] = rubber.get_env("ALIAS", "Hostname to use for staging instance", true, rails_env)
    default_roles = rubber_cfg.environment.bind().staging_roles || "*"
    roles = rubber.get_env("ROLES", "Roles to use for staging instance", true, default_roles)
    ENV['ROLES'] = roles 
    rubber.create
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
    Destroy the staging instance for the given RAILS_ENV.
  DESC
  task :destroy_staging do
    ENV['ALIAS'] = rubber.get_env("ALIAS", "Hostname of staging instance to be destroyed", true, rails_env)
    rubber.destroy
  end

  desc <<-DESC
    Live tail of rails log files for all machines
    By default tails the rails logs for the current RAILS_ENV, but one can
    set FILE=/path/file.*.glob to tails a different set
  DESC
  task :tail_logs, :roles => :app do
    log_file_glob = rubber.get_env("FILE", "Log files to tail", true, "#{current_path}/log/#{rails_env}*.log")
    run "tail -qf #{log_file_glob}" do |channel, stream, data|
      puts  # for an extra line break before the host name
      puts data
      break if stream == :err
    end
  end

  def bundle_vol(image_name)
    env = rubber_cfg.environment.bind()
    ec2_key = env.ec2_key_file
    ec2_pk = env.ec2_pk_file
    ec2_cert = env.ec2_cert_file
    aws_account = env.aws_account
    ec2_key_dest = "#{mnt_vol}/#{File.basename(ec2_key)}"
    ec2_pk_dest = "#{mnt_vol}/#{File.basename(ec2_pk)}"
    ec2_cert_dest = "#{mnt_vol}/#{File.basename(ec2_cert)}"
    
    put(File.read(ec2_key), ec2_key_dest)
    put(File.read(ec2_pk), ec2_pk_dest)
    put(File.read(ec2_cert), ec2_cert_dest)
    
    arch = capture "uname -m"
    arch = case arch when /i\d86/ then "i386" else arch end
    sudo_script "create_bundle", <<-CMD
      export RUBYLIB=/usr/lib/site_ruby/
      ec2-bundle-vol --batch -d #{mnt_vol} -k #{ec2_pk_dest} -c #{ec2_cert_dest} -u #{aws_account} -p #{image_name} -r #{arch}
    CMD
  end

  def upload_bundle(image_name)
    env = rubber_cfg.environment.bind()
    
    sudo_script "register_bundle", <<-CMD
      export RUBYLIB=/usr/lib/site_ruby/
      ec2-upload-bundle --batch -b #{env.ec2_image_bucket} -m #{mnt_vol}/#{image_name}.manifest.xml -a #{env.aws_access_key} -s #{env.aws_secret_access_key}
    CMD
    
    ec2 = EC2::Base.new(:access_key_id => env.aws_access_key, :secret_access_key => env.aws_secret_access_key)
    response = ec2.register_image(:image_location => "#{env.ec2_image_bucket}/#{image_name}.manifest.xml")
    logger.info "Newly registered AMI is: #{response.imageId}"
  end

  def describe_bundles
    env = rubber_cfg.environment.bind()

    ec2 = EC2::Base.new(:access_key_id => env.aws_access_key, :secret_access_key => env.aws_secret_access_key)
    response = ec2.describe_images(:owner_id => 'self')
    response.imagesSet.item.each do |item|
      logger.info "AMI: #{item.imageId}"
      logger.info "S3 Location: #{item.imageLocation}"
    end if response.imagesSet
  end

  def delete_bundle(ami)
    init_s3
    env = rubber_cfg.environment.bind()

    ec2 = EC2::Base.new(:access_key_id => env.aws_access_key, :secret_access_key => env.aws_secret_access_key)
    response = ec2.describe_images(:image_id => ami)
    image_location = response['DescribeImagesResponse'].imagesSet.item.imageLocation
    bucket = image_location.split('/').first
    image_name = image_location.split('/').last.gsub(/\.manifest\.xml$/, '')

    logger.info "De-registering image: #{ami}"
    ec2 = EC2::Base.new(:access_key_id => env.aws_access_key, :secret_access_key => env.aws_secret_access_key)
    response = ec2.deregister_image(:image_id => ami)
    
    s3_bucket = AWS::S3::Bucket.find(bucket) 
    s3_bucket.objects(:prefix => image_name).clone.each do |obj|
      logger.info "Deleting image bundle file: #{obj.key}"
      obj.delete
    end
    if s3_bucket.empty?
      logger.info "Removing empty bucket: #{s3_bucket.name}"
      s3_bucket.delete 
    end
  end

  def run_config(options={})
    path = options.delete(:deploy_path) || current_path
    extra_env = options.keys.inject("") {|all, k|  "#{all} #{k}=\"#{options[k]}\""}

    # Need to do this so we can work with staging instances without having to
    # checkin instance file between create and bootstrap, as well as during a deploy
    if fetch(:push_instance_config, false)
      push_files = [rubber_cfg.instance.file] + rubber_cfg.environment.config_files
      push_files.each do |file|
        dest_file = file.sub(/^#{RAILS_ROOT}\/?/, '')
        put(File.read(file), File.join(path, dest_file))
      end
    end
    
    # if the user has defined a secret config file, then push it into RAILS_ROOT/config/rubber
    secret = rubber_cfg.environment.config_secret
    if secret && File.exist?(secret)
      base = rubber_cfg.environment.config_root.sub(/^#{RAILS_ROOT}\/?/, '')
      put(File.read(secret), File.join(path, base, File.basename(secret)))
    end
    
    sudo "sh -c 'cd #{path} && #{extra_env} rake rubber:config'"
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

  # Creates a new ec2 instance with the given alias and roles
  # Configures aliases (/etc/hosts) on local and remote machines
  def create_instance(instance_alias, instance_roles)
    fatal "Instance already exists: #{instance_alias}" if rubber_cfg.instance[instance_alias]

    role_names = instance_roles.collect{|x| x.name}
    env = rubber_cfg.environment.bind(role_names, instance_alias)
    ec2 = EC2::Base.new(:access_key_id => env.aws_access_key, :secret_access_key => env.aws_secret_access_key)
    
    # We need to use security_groups during create, so create them up front
    security_groups = env.security_groups
    security_group_defns = env.ec2_security_groups
    if env.auto_security_groups
      hosts = rubber_cfg.instance.collect{|ic| ic.name } + [instance_alias]
      roles = (rubber_cfg.instance.all_roles + role_names).uniq
      security_groups << instance_alias
      security_groups += role_names
      security_groups.uniq!
      security_group_defns = inject_auto_security_groups(security_group_defns, hosts, roles)
      sync_security_groups(security_group_defns)
    else
      sync_security_groups(security_group_defns)
    end
    
    ami = env.ec2_instance
    ami_type = env.ec2_instance_type
    availability_zone = env.availability_zone
    logger.info "Creating instance #{ami}/#{ami_type}/#{security_groups.join(',') rescue 'Default'}/#{availability_zone || 'Default'}"
    response = ec2.run_instances(:image_id => ami, :key_name => env.ec2_key_name, :instance_type => ami_type, :group_id => security_groups, :availability_zone => availability_zone)
    item = response.instancesSet.item[0]
    instance_id = item.instanceId

    logger.info "Instance #{instance_id} created"

    instance_item = Rubber::Configuration::InstanceItem.new(instance_alias, env.domain, instance_roles, instance_id)
    rubber_cfg.instance.add(instance_item)
    rubber_cfg.instance.save()


    print "Waiting for instance to start"
    while true do
      print "."
      sleep 2
      response = ec2.describe_instances(:instance_id => instance_id)
      item = response.reservationSet.item[0].instancesSet.item[0]
      if item.instanceState.name == "running"
        logger.info "\nInstance running, fetching hostname/ip data"
        instance_item.external_host = item.dnsName
        instance_item.external_ip = IPSocket.getaddress(item.dnsName)
        instance_item.internal_host = item.privateDnsName

        # setup amazon elastic ips if configured to do so
        setup_static_ips
        
        # Need to setup aliases so ssh doesn't give us errors when we
        # later try to connect to same ip but using alias
        setup_local_aliases

        # re-load the roles since we may have just defined new ones
        load_roles() unless env.disable_auto_roles

        # Connect to newly created instance and grab its internal ip
        # so that we can update all aliases
        task :_get_ip, :hosts => instance_item.external_host do
          instance_item.internal_ip = capture("curl -s http://169.254.169.254/latest/meta-data/local-ipv4").strip
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

    rubber_cfg.instance.save()
  end

  # Refreshes a ec2 instance with the given alias
  # Configures aliases (/etc/hosts) on local and remote machines
  def refresh_instance(instance_alias)
    instance_item = rubber_cfg.instance[instance_alias]
    
    fatal "Instance does not exist: #{instance_alias}" if ! instance_item

    env = rubber_cfg.environment.bind(instance_item.role_names, instance_alias)
    ec2 = EC2::Base.new(:access_key_id => env.aws_access_key, :secret_access_key => env.aws_secret_access_key)
    response = ec2.describe_instances(:instance_id => instance_item.instance_id)
    item = response.reservationSet.item[0].instancesSet.item[0]
    if item.instanceState.name == "running"
      logger.info "\nInstance running, fetching hostname/ip data"
      instance_item.external_host = item.dnsName
      instance_item.external_ip = IPSocket.getaddress(item.dnsName)
      instance_item.internal_host = item.privateDnsName

      # Need to setup aliases so ssh doesn't give us errors when we
      # later try to connect to same ip but using alias
      setup_local_aliases

      # re-load the roles since we may have just defined new ones
      load_roles() unless env.disable_auto_roles

      # Connect to newly created instance and grab its internal ip
      # so that we can update all aliases
      task :_get_ip, :hosts => instance_item.full_name do
        instance_item.internal_ip = capture("curl -s http://169.254.169.254/latest/meta-data/local-ipv4").strip
      end
      # even though instance is running, we need to give ssh a chance
      # to get started
      sleep 5
      _get_ip

      # Add the aliases for this instance to all other hosts
      setup_remote_aliases
      setup_dns_aliases
    end

    rubber_cfg.instance.save()
  end


  # Destroys the given ec2 instance
  def destroy_instance(instance_alias)
    instance_item = rubber_cfg.instance[instance_alias]
    fatal "Instance does not exist: #{instance_alias}" if ! instance_item
    
    env = rubber_cfg.environment.bind(instance_item.role_names, instance_item.name)

    value = Capistrano::CLI.ui.ask("About to DESTROY #{instance_alias} (#{instance_item.instance_id}) in mode #{ENV['RAILS_ENV']}.  Are you SURE [yes/NO]?: ")
    fatal("Exiting", 0) if value != "yes"
    
    if env.use_static_ip && instance_item.static_ip
      value = Capistrano::CLI.ui.ask("Instance has a static ip, do you want to release it? [y/N]?: ")
      deallocate_static_ip(instance_item.static_ip) if value =~ /^y/
    end
    
    logger.info "Destroying instance alias=#{instance_alias}, instance_id=#{instance_item.instance_id}"
    ec2 = EC2::Base.new(:access_key_id => env.aws_access_key, :secret_access_key => env.aws_secret_access_key)
    response = ec2.terminate_instances(:instance_id => instance_item.instance_id)

    rubber_cfg.instance.remove(instance_alias)
    rubber_cfg.instance.save()

    # re-load the roles since we just removed some and setup_remote_aliases
    # shouldn't hit removed ones
    load_roles() unless env.disable_auto_roles

    setup_aliases
    destroy_dyndns(instance_item)
    cleanup_known_hosts(instance_alias) unless env.disable_known_hosts_cleanup
  end
  
  # delete from ~/.ssh/known_hosts all lines that begin with ec2- or instance_alias
  def cleanup_known_hosts(instance_alias)
    logger.info "Cleaning ~/.ssh/known_hosts"
    File.open(File.expand_path('~/.ssh/known_hosts'), 'r+') do |f|   
        out = ""
        f.each do |line|
          line = case line
            when /^ec2-/; ''
            when /^#{instance_alias}/; ''
            else line;
          end
          out << line
        end
        f.pos = 0                     
        f.print out
        f.truncate(f.pos)             
    end    
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
        opts["hostvar_#{ic.full_name}"] = cfg_value
      end
    end
    return opts
  end

  def package_helper(upgrade=false)
    opts = get_host_options('packages') { |x| x.join(' ') }
    sudo "apt-get -q update", opts
    if upgrade
      sudo "/bin/sh -c 'export DEBIAN_FRONTEND=noninteractive; apt-get -q -y --force-yes dist-upgrade'", opts
    else
      sudo "/bin/sh -c 'export DEBIAN_FRONTEND=noninteractive; apt-get -q -y --force-yes install $CAPISTRANO:VAR$'", opts
    end
  end
  
  def custom_package(url_base, name, ver, install_test)
    rubber.run_script "install_#{name}", <<-ENDSCRIPT
      if [[ #{install_test} ]]; then
        arch=`uname -m`
        if [ "$arch" = "x86_64" ]; then
          src="#{url_base}/#{name}_#{ver}_amd64.deb"
        else
          src="#{url_base}/#{name}_#{ver}_i386.deb"
        fi
        src_file="${src##*/}"
        wget -qP /tmp ${src}
        dpkg -i /tmp/${src_file}
      fi
    ENDSCRIPT
  end    

  # Helper for installing gems,allows one to respond to prompts
  def gem_helper(update=false)
    cmd = update ? "update" : "install"
    opts = get_host_options('gems') { |x| x.join(' ') }
    sudo "gem #{cmd} $CAPISTRANO:VAR$ --no-rdoc --no-ri", opts do |ch, str, data|
      ch[:data] ||= ""
      ch[:data] << data
      if data =~ />\s*$/
        logger.info data
        logger.info "The gem command is asking for a number:"
        choice = STDIN.gets
        ch.send_data(choice)
      else
        logger.info data
      end
    end
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

  def update_dyndns(instance_item)
    env = rubber_cfg.environment.bind(instance_item.role_names, instance_item.name)
    if env.dns_provider
      provider = DynamicDnsBase.get_provider(env.dns_provider, env)
      provider.update(instance_item.name, instance_item.external_ip)
    end
  end

  def destroy_dyndns(instance_item)
    env = rubber_cfg.environment.bind(instance_item.role_names, instance_item.name)
    if env.dns_provider
      provider = DynamicDnsBase.get_provider(env.dns_provider, env)
      provider.destroy(instance_item.name)
    end
  end
  
  def init_s3()
    Rubber::Configuration.init_s3(rubber_cfg.environment.bind())
  end

  def allocate_static_ip(ic)
    env = rubber_cfg.environment.bind()
    ec2 = EC2::Base.new(:access_key_id => env.aws_access_key, :secret_access_key => env.aws_secret_access_key)
    logger.info "Allocating static ip for #{ic.full_name}"
    response = ec2.allocate_address()
    ic.static_ip = response.publicIp
    rubber_cfg.instance.save()
  end
    
  def associate_static_ip(ic)
    env = rubber_cfg.environment.bind()
    ec2 = EC2::Base.new(:access_key_id => env.aws_access_key, :secret_access_key => env.aws_secret_access_key)
    logger.info "Associating static ip to instance: #{ic.full_name} (#{ic.instance_id}) => #{ic.static_ip}"
    response = ec2.associate_address(:instance_id => ic.instance_id, :public_ip => ic.static_ip)
    if response.return == "true"
      ic.external_ip = ic.static_ip
      response = ec2.describe_instances(:instance_id => ic.instance_id)
      item = response.reservationSet.item[0].instancesSet.item[0]
      ic.external_host = item.dnsName
      ic.internal_host = item.privateDnsName
      rubber_cfg.instance.save()
    else
      fatal "Failed to associate static ip"
    end
  end

  def deallocate_static_ip(instance_ip)
    env = rubber_cfg.environment.bind()
    ec2 = EC2::Base.new(:access_key_id => env.aws_access_key, :secret_access_key => env.aws_secret_access_key)
    logger.info "DeAllocating static ip: #{instance_ip}"
    response = ec2.release_address(:public_ip => instance_ip)
    fatal "Failed to deallocate" if response.return != "true"
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

  # Automatically load and define capistrano roles from instance config
  def load_roles
    top.roles.clear

    # define empty roles for all known ones so tasks don't fail if a role
    # doesn't exist due to a filter
    all_roles = rubber_cfg.instance.all_roles
    all_roles += rubber_cfg.environment.known_roles
    all_roles.uniq!
    all_roles.each {|name| top.roles[name.to_sym] = []}

    # define capistrano host => role mapping for all instances
    rubber_cfg.instance.filtered.each do |ic|
      ic.roles.each do |role|
        opts = Rubber::Util::symbolize_keys(role.options)
        msg = "Auto role: #{role.name.to_sym} => #{ic.full_name}"
        msg << ", #{opts.inspect}" if opts.inspect.size > 0
        logger.info msg
        top.role role.name.to_sym, ic.full_name, opts
      end
    end
  end

end
