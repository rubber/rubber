# add this plugins lib dir to load path for capistrano
$:.unshift "#{File.dirname(__FILE__)}/../lib"

require "socket"
require 'resolv'
require 'rubber/util'
require 'rubber/configuration'

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
    Create a new EC2 instance with the given ALIAS and ROLE
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
      ir << role
    end
    create_instance(instance_alias, ir)
  end

  desc <<-DESC
    Refresh the host data for a EC2 instance with the given ALIAS
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
    Bootstraps instances by setting timezone, installing packages and gems
  DESC
  task :bootstrap do
    set_timezone
    install_packages
    install_rubygems
    install_gems
    bootstrap_db
  end

  desc <<-DESC
    Bootstrap the production database config
  DESC
  task :bootstrap_db, :roles => :db do
    env = rubber_cfg.environment.bind(nil, nil)
    if env.db_config
      # After everything installed on machines, we need the source tree
      # on hosts in order to run rubber:config for bootstrapping the db
      deploy.setup
      deploy.update_code
      # Gen mysql conf because we need a functioning db before we can migrate
      # Its up to user to create initial DB in mysql.cnf @post
      rubber.run_config(:deploy_path => release_path, :RAILS_ENV => rails_env, :NO_ENV => true, :FILE => env.db_config)
    end
  end


  desc <<-DESC
    Sets up aliases for instance hostnames based on contents of instance.yml.
    Generates/etc/hosts for local/remote machines and sets hostname on remote instances
  DESC
  task :setup_aliases do
    setup_local_aliases
    setup_remote_aliases
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
      full_name = ic.name + "." + rubber_cfg.environment.bind(ic.roles.first.name, ic.name).domain
      hosts_data = [ic.name, full_name, ic.external_host, ic.internal_host].join(' ')
      local_hosts << ic.external_ip << ' ' << hosts_data << "\n"
      update_dyndns(full_name, ic.external_ip)
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
      full_name = ic.name + "." + rubber_cfg.environment.bind(ic.roles.first.name, ic.name).domain
      hosts_data = [ic.name, full_name, ic.external_host, ic.internal_host].join(' ')
      remote_hosts << ic.internal_ip << ' ' << hosts_data << "\n"
    end
    remote_hosts << delim << "\n"

    # write out the hosts file for the remote instances
    # NOTE that we use "capture" to get the existing hosts
    # file, which only grabs the hosts file from the first host
    filtered = (capture "cat #{hosts_file}").gsub(/^#{delim}.*^#{delim}\n?/m, '')
    filtered = filtered + remote_hosts
    # Put the generated hosts back on remote instance
    put filtered, hosts_file

    # Setup hostname on instance so shell, etcs have nice display
    run "echo $CAPISTRANO:HOST$ > /etc/hostname && hostname $CAPISTRANO:HOST$"

    # TODO
    # /etc/resolv.conf to add search domain
    # ~/.ssh/options to setup user/host/key aliases
  end

  desc <<-DESC
    Update to the newest versions of all packages/gems.
  DESC
  task :update do
    update_packages
    update_gems
  end

  desc <<-DESC
    Upgrade to the newest versions of all Ubuntu packages.
  DESC
  task :update_packages do
    package_helper('', true)
  end

  desc <<-DESC
    Upgrade to the newest versions of all rubygems.
  DESC
  task :update_gems do
    execute_for_scopes('gems') do |cfg_value|
      # run "echo `hostname`: #{cfg_value.join(' ')}" }
      gem_helper(cfg_value, true)
    end
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
    execute_for_scopes('packages') do |cfg_value|
      package_helper(cfg_value, false)
    end
  end

  desc <<-DESC
    Install extra ruby gems. Set 'gems' in rubber.yml to \
    be an array of strings.
  DESC
  task :install_gems do
    execute_for_scopes('gems') do |cfg_value|
      # run "echo `hostname`: #{cfg_value.join(' ')}" }
      gem_helper(cfg_value, false)
    end
  end

  desc <<-DESC
    The ubuntu rubygem package is woefully out of date, so install it manually
  DESC
  task :install_rubygems do
    rubber.run_script 'install_rubygems', <<-ENDSCRIPT
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
    Set the timezone using the value of the variable named timezone. \
    Valid options for timezone can be determined by the contents of \
    /usr/share/zoneinfo, which can be seen here: \
    http://packages.ubuntu.com/cgi-bin/search_contents.pl?searchmode=filelist&word=tzdata&version=gutsy&arch=all&page=1&number=all \
    Remove 'usr/share/zoneinfo/' from the filename, and use the last \
    directory and file as the value. For example 'Africa/Abidjan' or \
    'posix/GMT' or 'Canada/Eastern'.
  DESC
  task :set_timezone do
    execute_for_scopes('timezone') do |cfg_value|
      # run "echo `hostname`: #{cfg_value.join(' ')}" }
      sudo "bash -c 'echo #{cfg_value} > /etc/timezone'"
      sudo "cp /usr/share/zoneinfo/#{cfg_value} /etc/localtime"
    end
  end

  desc <<-DESC
    Configures the deployed rails application by running the rubber configuration process
  DESC
  task :config do
    opts = {}
    opts['NO_ENV'] = true if ENV['NO_ENV']
    opts['NO_POST'] = true if ENV['NO_POST']
    opts['FILE'] = ENV['FILE'] if ENV['FILE']
    opts['RAILS_ENV'] = ENV['RAILS_ENV'] if ENV['RAILS_ENV']
    run_config(opts)
  end

  def run_config(options={})
    path = options.delete(:deploy_path) || current_path
    extra_env = options.keys.inject("") {|all, k|  "#{all} #{k}='#{options[k]}'"}
    put(File.read(rubber_cfg.environment.file), "#{path}/#{rubber_cfg.environment.file}")
    put(File.read(rubber_cfg.instance.file), "#{path}/#{rubber_cfg.instance.file}")
    run "cd #{path} && #{extra_env} rake rubber:config"
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
    env = rubber_cfg.environment.bind(instance_roles.first.name, instance_alias)
    ec2 = EC2::Base.new(:access_key_id => env.aws_access_key, :secret_access_key => env.aws_secret_access_key)
    ami = env.ec2_instance
    ami_type = env.ec2_instance_type
    response = ec2.run_instances(:image_id => ami, :key_name => env.ec2_key_name, :instance_type => ami_type)
    item = response.instancesSet.item[0]
    instance_id = item.instanceId

    puts "Instance created, id=#{instance_id}"

    instance_item = Rubber::Configuration::InstanceItem.new(instance_alias, instance_roles, instance_id)
    rubber_cfg.instance.add(instance_item)
    rubber_cfg.instance.save()


    print "Waiting for instance to start"
    while true do
      print "."
      sleep 5
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
        # even though instance is running, we need to give ssh a chance
        # to get started
        sleep 5
        _get_ip

        # Add the aliases for this instance to all other hosts
        setup_remote_aliases

        break
      end
    end

    rubber_cfg.instance.save()
  end

  # Refreshes a ec2 instance with the given alias
  # Configures aliases (/etc/hosts) on local and remote machines
  def refresh_instance(instance_alias)
    instance_item = rubber_cfg.instance[instance_alias]
    env = rubber_cfg.environment.bind(instance_item.roles.first.name, instance_alias)
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
      task :_get_ip, :hosts => instance_item.name do
        instance_item.internal_ip = capture("curl -s http://169.254.169.254/latest/meta-data/local-ipv4").strip
      end
      # even though instance is running, we need to give ssh a chance
      # to get started
      sleep 5
      _get_ip

      # Add the aliases for this instance to all other hosts
      setup_remote_aliases
    end

    rubber_cfg.instance.save()
  end



  # Destroys the given ec2 instance
  def destroy_instance(instance_alias)
    value = Capistrano::CLI.ui.ask("About to DESTROY #{instance_alias} in mode #{ENV['RAILS_ENV']}.  Are you SURE [yes/NO]?: ")
    if value != "yes"
      puts "Exiting"
      exit
    end
    instance_item = rubber_cfg.instance[instance_alias]
    env = rubber_cfg.environment.bind(instance_item.roles.first.name, instance_item.name)

    puts "Destroying instance alias=#{instance_alias}, instance_id=#{instance_item.instance_id}"
    ec2 = EC2::Base.new(:access_key_id => env.aws_access_key, :secret_access_key => env.aws_secret_access_key)
    response = ec2.terminate_instances(:instance_id => instance_item.instance_id)

    rubber_cfg.instance.remove(instance_alias)
    rubber_cfg.instance.save()
  end

  # Looks up the given config value and runs the given block for each scope (common, roles, host)
  # This is used to run capistrano tasks scoped to the correct role/host so that a config value
  # specific to a role/host will only be used for that role/host, e.g. the list of packages to
  # be installed.  Does not run the block for a role/host if it has already been run for that
  # config value at a higher scope
  def execute_for_scopes(cfg_name)
    seen = {}
    env = rubber_cfg.environment.bind(nil, nil)
    cfg_value = env[cfg_name]
    if cfg_value
      puts "Installing global #{cfg_name}"
      seen[cfg_value] = true
      yield cfg_value
    end

    instance_roles = [], instance_hosts = []
    rubber_cfg.instance.each do | ic|
      instance_hosts << ic.name
      instance_roles.concat(ic.roles.collect{|r| r.name})
    end
    instance_hosts = instance_hosts.compact.uniq
    instance_roles = instance_roles.compact.uniq

    first = true
    instance_roles.each do |r|
      env = rubber_cfg.environment.bind(r, nil)
      cfg_value = env[cfg_name]
      if cfg_value and ! seen[cfg_value]
        puts "Installing role specific #{cfg_name}" if first; first = false
        (seen[r] ||= {})[cfg_value] = true
        task "install_#{cfg_name}_#{r}", :roles => r do
          yield cfg_value
        end
        eval "install_#{cfg_name}_#{r}"
      end
    end

    first = true
    instance_hosts.each do |h|
      env = rubber_cfg.environment.bind(nil, h)
      cfg_value = env[cfg_name]
      hosts_roles_already_seen = rubber_cfg.instance[h].roles.any? {|r| seen[r.name][cfg_value] rescue nil }
      if cfg_value && ! seen[cfg_value] && ! hosts_roles_already_seen
        puts "Installing host specific #{cfg_name}" if first; first = false
        task "install_#{cfg_name}_#{h}", :hosts => h do
          yield cfg_value
        end
        eval "install_#{cfg_name}_#{h}"
      end
    end
  end

  def package_helper(packages, update=false)
    pkgs = packages.join(' ') rescue nil
    if update
      sudo "aptitude -q update"
      run "export DEBIAN_FRONTEND=noninteractive; sudo aptitude -q -y " + (pkgs ? "update #{pkgs}" : "dist-upgrade")
    else
      # run "echo `hostname`: #{cfg_value.join(' ')}" }
      run "export DEBIAN_FRONTEND=noninteractive; sudo aptitude -q -y install #{pkgs}"
    end
  end

  # Helper for installing gems,allows one to respond to prompts
  def gem_helper(gems, update=false)
    cmd = update ? "update" : "install"
    sudo "gem #{cmd} #{gems.join(' ')} --no-rdoc --no-ri" do |ch, str, data|
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

  def run_script(name, contents)
    script = "/tmp/#{name}"
    put(contents, script)
    sudo "sh #{script}"
  end

  def update_dyndns(instance_host, instance_ip)
    cfg = rubber_cfg.environment.bind(nil, nil)
    user, pass = cfg.dyndns_user, cfg.dyndns_password
    update_url = cfg.dyndns_update_url
    if update_url && user
      current_ip = Resolv.getaddress(instance_host) rescue nil
      if instance_ip == current_ip
        puts "IP has not changed, not updating dynamic DNS"
        return
      end

      update_url = eval "\"#{update_url}\""
      puts "Updating dynamic DNS: #{instance_host} => #{instance_ip}"
      puts "Using update url: #{update_url}"
      # This header is required by dyndns.org
      headers = {
       "User-Agent" => "Capistrano - Rubber - 0.1"
      }

      uri = URI.parse(update_url)
      http = Net::HTTP.new(uri.host, uri.port)
      # switch on SSL
      http.use_ssl = true if uri.scheme == "https"
      # suppress verification warning
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      req = Net::HTTP::Get.new(update_url.gsub(/.*:\/\/[^\/]*/, ''), headers)
      # authentication details
      req.basic_auth user, pass
      resp = http.request(req)
      # print out the response for the update
      puts "Dynamic DNS Update result: #{resp.body}"
    end
  end

  # Automatically load and define capistrano roles from instance config
  def load_roles
    rubber_cfg.instance.each do |ic|
      ic.roles.each do |role|
        opts = Rubber::Util::symbolize_keys(role.options)
        msg = "Auto role: #{role.name.to_sym} => #{ic.name}"
        msg << ", #{opts.inspect}" if opts.inspect.size > 0
        puts msg
        top.role role.name.to_sym, ic.name, opts
      end
    end
  end

end
