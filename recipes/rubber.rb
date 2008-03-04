# add this plugins lib dir to load path for capistrano
$:.unshift "#{File.dirname(__FILE__)}/../lib"

require "socket"
require 'resolv'
require 'rubber/util'
require 'rubber/configuration'
require 'capistrano/hostcmd'

require 'rubygems'
require 'ec2'

namespace :rubber do

  on :load, "rubber:init"

  task :init do
    set :rubber_cfg, Rubber::Configuration.get_configuration(ENV['RAILS_ENV'])
    load_roles() unless rubber_cfg.environment.bind(nil, nil).disable_auto_roles
    # NOTE: for some reason Capistrano requires you to have both the public and
    # the private key in the same folder, the public key should have the
    # extension ".pub".
    ssh_options[:keys] = File.expand_path(rubber_cfg.environment.bind(nil, nil).ec2_key_file)
  end

  desc <<-DESC
    Create a new EC2 instance with the given ALIAS and ROLES
  DESC
  task :create do
    instance_alias = get_env('ALIAS', "Instance alias (e.g. web01)", true)
    r = get_env('ROLES', "Instance roles (e.g. web,app,db:primary=true)", true)
    if r == '*'
      instance_roles = rubber_cfg.environment.known_roles
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
        if value =~ /^y/
          role.options["primary"] = true
        end
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
    refresh_instance(instance_alias)
  end

  desc <<-DESC
    Destroy the EC2 instance for the given ALIAS
  DESC
  task :destroy do
    instance_alias = get_env('ALIAS', "Instance alias (e.g. web01)", true)
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
    Bootstraps instances by setting timezone, installing packages and gems
  DESC
  task :bootstrap do
    set_timezone
    link_bash
    install_packages
    install_rubygems
    install_gems
    bootstrap_db
  end

  desc <<-DESC
    Bootstrap the production database config.  Db bootstrap is special - the
    user could be requiring the rails env inside some of their config
    templates, which creates a catch 22 situation with the db, so we try and
    bootstrap the db separate from the rest of the config
  DESC
  task :bootstrap_db, :roles => :db do
    env = rubber_cfg.environment.bind("db", nil)
    if env.db_config
      # After everything installed on machines, we need the source tree
      # on hosts in order to run rubber:config for bootstrapping the db
      deploy.setup
      deploy.update_code
      # Gen mysql conf because we need a functioning db before we can migrate
      # Its up to user to create initial DB in mysql.cnf @post
      rubber.run_config(:deploy_path => release_path, :RAILS_ENV => rails_env, :FILE => env.db_config)
    end
  end


  desc <<-DESC
    Sets up aliases for instance hostnames based on contents of instance.yml.
    Generates /etc/hosts for local/remote machines and sets hostname on
    remote instances, and sets values in dynamic dns entries
  DESC
  task :setup_aliases do
    setup_local_aliases
    setup_remote_aliases
    setup_dns_aliases
  end

  desc <<-DESC
    Sets up local aliases for instance hostnames based on contents of instance.yml.
    Generates/etc/hosts for local machine
  DESC
  task :setup_local_aliases do
    hosts_file = '/etc/hosts'

    # Generate /etc/hosts contents for the local machine from instance config
    env = rubber_cfg.environment.bind(nil, nil)
    delim = "## rubber config #{env.domain} #{ENV['RAILS_ENV']}"
    local_hosts = delim + "\n"
    rubber_cfg.instance.each do |ic|
      env = rubber_cfg.environment.bind(ic.role_names, ic.name)
      # don't add unqualified hostname in local hosts file since user may be
      # managing multiple domains with same aliases
      hosts_data = [ic.full_name, ic.external_host, ic.internal_host].join(' ')
      local_hosts << ic.external_ip << ' ' << hosts_data << "\n"
    end
    local_hosts << delim << "\n"

    # Write out the hosts file for this machine, use sudo
    filtered = File.read(hosts_file).gsub(/^#{delim}.*^#{delim}\n?/m, '')
    puts "Writing out aliases into local machines #{hosts_file}, sudo access needed"
    Rubber::Util::sudo_open(hosts_file, 'w') do |f|
      f.write(filtered)
      f.write(local_hosts)
    end
  end

  desc <<-DESC
    Sets up aliases in dynamic dns provider for instance hostnames based on contents of instance.yml.
  DESC
  task :setup_dns_aliases do
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
      env = rubber_cfg.environment.bind(ic.roles.first.name, ic.name)
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
    The ubuntu rubygem package is woefully out of date, so install it manually
  DESC
  task :install_rubygems do
    rubber.sudo_script 'install_rubygems', <<-ENDSCRIPT
      if [ ! -f /usr/bin/gem ]; then
        wget -qP /tmp http://rubyforge.org/frs/download.php/29548/rubygems-1.0.1.tgz
        tar -C /tmp -xzf /tmp/rubygems-1.0.1.tgz
        ruby -C /tmp/rubygems-1.0.1 setup.rb
        ln -sf /usr/bin/gem1.8 /usr/bin/gem
        rm -rf /tmp/rubygems*
        gem source -l > /dev/null
      fi
    ENDSCRIPT
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
    run_config(opts)
  end

  def run_config(options={})
    path = options.delete(:deploy_path) || current_path
    extra_env = options.keys.inject("") {|all, k|  "#{all} #{k}='#{options[k]}'"}
    dest_env_file = rubber_cfg.environment.file.sub(/^#{RAILS_ROOT}/, '')
    put(File.read(rubber_cfg.environment.file), "#{path}/#{dest_env_file}")
    dest_instance_file = rubber_cfg.instance.file.sub(/^#{RAILS_ROOT}/, '')
    put(File.read(rubber_cfg.instance.file), "#{path}/#{dest_instance_file}")
    sudo "sh -c 'cd #{path} && #{extra_env} rake rubber:config'"
  end

  def get_env(name, desc, required=false)
    value = ENV.delete(name)
    value = Capistrano::CLI.ui.ask("#{desc}: ") unless value
    raise("#{name} is required, pass using environment or enter at prompt") if required && ! value
    return value
  end

  # Creates a new ec2 instance with the given alias and roles
  # Configures aliases (/etc/hosts) on local and remote machines
  def create_instance(instance_alias, instance_roles)
    if rubber_cfg.instance[instance_alias]
      puts "Instance already exists: #{instance_alias}"
      exit 1
    end

    env = rubber_cfg.environment.bind(instance_roles.collect{|x| x.name}, instance_alias)
    ec2 = EC2::Base.new(:access_key_id => env.aws_access_key, :secret_access_key => env.aws_secret_access_key)
    ami = env.ec2_instance
    ami_type = env.ec2_instance_type
    response = ec2.run_instances(:image_id => ami, :key_name => env.ec2_key_name, :instance_type => ami_type)
    item = response.instancesSet.item[0]
    instance_id = item.instanceId

    puts "Instance #{instance_id} created"

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
        puts "\nInstance running, fetching hostname/ip data"
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
        task :_get_ip, :hosts => instance_item.external_host do
          instance_item.internal_ip = capture("curl -s http://169.254.169.254/latest/meta-data/local-ipv4").strip
        end

        # even though instance is running, sometimes ssh hasn't started yet,
        # so retry on connect failure
        begin
          _get_ip
        rescue ConnectionError
          sleep 2
          puts "Failed to connect to #{instance_alias} (#{instance_item.external_ip}), retrying"
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
    if ! instance_item
      puts "Instance does not exist: #{instance_alias}"
      exit 1
    end

    env = rubber_cfg.environment.bind(instance_item.role_names, instance_alias)
    ec2 = EC2::Base.new(:access_key_id => env.aws_access_key, :secret_access_key => env.aws_secret_access_key)
    response = ec2.describe_instances(:instance_id => instance_item.instance_id)
    item = response.reservationSet.item[0].instancesSet.item[0]
    if item.instanceState.name == "running"
      puts "\nInstance running, fetching hostname/ip data"
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
    if ! instance_item
      puts "Instance does not exist: #{instance_alias}"
      exit 1
    end
    env = rubber_cfg.environment.bind(instance_item.role_names, instance_item.name)

    value = Capistrano::CLI.ui.ask("About to DESTROY #{instance_alias} (#{instance_item.instance_id}) in mode #{ENV['RAILS_ENV']}.  Are you SURE [yes/NO]?: ")
    if value != "yes"
      puts "Exiting"
      exit
    end

    puts "Destroying instance alias=#{instance_alias}, instance_id=#{instance_item.instance_id}"
    ec2 = EC2::Base.new(:access_key_id => env.aws_access_key, :secret_access_key => env.aws_secret_access_key)
    response = ec2.terminate_instances(:instance_id => instance_item.instance_id)

    rubber_cfg.instance.remove(instance_alias)
    rubber_cfg.instance.save()

    # re-load the roles since we just removed some and setup_remote_aliases
    # shouldn't hit removed ones
    load_roles() unless env.disable_auto_roles

    setup_aliases
    destroy_dyndns(instance_item)
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
      run "export DEBIAN_FRONTEND=noninteractive; sudo apt-get -q -y dist-upgrade", opts
    else
      run "export DEBIAN_FRONTEND=noninteractive; sudo apt-get -q -y install $CAPISTRANO:VAR$", opts
    end
  end

  # Helper for installing gems,allows one to respond to prompts
  def gem_helper(update=false)
    cmd = update ? "update" : "install"
    opts = get_host_options('gems') { |x| x.join(' ') }
    sudo "gem #{cmd} $CAPISTRANO:VAR$ --no-rdoc --no-ri", opts do |ch, str, data|
      ch[:data] ||= ""
      ch[:data] << data
      if data =~ />\s*$/
        puts data
        puts "The gem command is asking for a number:"
        choice = STDIN.gets
        ch.send_data(choice)
      else
        puts data
      end
    end
  end


  def prepare_script(name, contents)
    script = "/tmp/#{name}"
    # this lets us abort a script if a command in the middle of it errors out
    env = rubber_cfg.environment.bind(nil, nil)
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

  # Automatically load and define capistrano roles from instance config
  def load_roles
    top.roles.clear
    rubber_cfg.instance.each do |ic|
      ic.roles.each do |role|
        opts = Rubber::Util::symbolize_keys(role.options)
        msg = "Auto role: #{role.name.to_sym} => #{ic.full_name}"
        msg << ", #{opts.inspect}" if opts.inspect.size > 0
        puts msg
        top.role role.name.to_sym, ic.full_name, opts
      end
    end
  end

end
