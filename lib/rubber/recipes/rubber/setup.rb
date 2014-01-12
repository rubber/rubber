require "bundler/capistrano" if Rubber::Util.is_bundler?

namespace :rubber do

  desc <<-DESC
    Bootstraps instances by setting timezone, installing packages and gems
  DESC
  task :bootstrap do
    link_bash
    set_timezone
    enable_multiverse
    install_core_packages
    upgrade_packages
    install_packages
    setup_volumes
    setup_gem_sources
    install_gems
    deploy.setup
  end

  # Sets up instance to allow root access (e.g. recent canonical AMIs)
  def enable_root_ssh(ip, initial_ssh_user)
    # Capistrano uses the :password variable for sudo commands.  Since this setting is generally used for the deploy user,
    # but we need it this one time for the initial SSH user, we need to swap out and restore the password.
    #
    # We special-case the 'ubuntu' user since the Canonical AMIs on EC2 don't set the password for
    # this account, making any password prompt potentially confusing.
    orig_password = fetch(:password)
    initial_ssh_password = fetch(:initial_ssh_password, nil)

    if initial_ssh_user == 'ubuntu' || ENV.has_key?('RUN_FROM_VAGRANT')
      set(:password, nil)
    elsif initial_ssh_password
      set(:password, initial_ssh_password)
    else
      set(:password, Capistrano::CLI.password_prompt("Password for #{initial_ssh_user} @ #{ip}: "))
    end

    task :_ensure_key_file_present, :hosts => "#{initial_ssh_user}@#{ip}" do
      public_key_filename = "#{cloud.env.key_file}.pub"

      if File.exists?(public_key_filename)
        public_key = File.read(public_key_filename).chomp

        rubber.sudo_script 'ensure_key_file_present', <<-ENDSCRIPT
          mkdir -p ~/.ssh
          touch ~/.ssh/authorized_keys
          chmod 600 ~/.ssh/authorized_keys

          if ! grep -q '#{public_key}' .ssh/authorized_keys; then
            echo '#{public_key}' >> .ssh/authorized_keys
          fi
        ENDSCRIPT
      end
    end

    task :_allow_root_ssh, :hosts => "#{initial_ssh_user}@#{ip}" do
      rsudo "mkdir -p /root/.ssh && cp /home/#{initial_ssh_user}/.ssh/authorized_keys /root/.ssh/"
    end

    task :_disable_password_based_ssh_login, :hosts => "#{initial_ssh_user}@#{ip}" do
      rubber.sudo_script 'disable_password_based_ssh_login', <<-ENDSCRIPT
        if ! grep -q 'PasswordAuthentication no' /etc/ssh/sshd_config; then
          echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config
          service ssh restart
        fi
      ENDSCRIPT
    end

    begin
      _ensure_key_file_present
      _allow_root_ssh
      _disable_password_based_ssh_login if cloud.should_disable_password_based_ssh_login?
    rescue ConnectionError => e
      if e.message =~ /Net::SSH::AuthenticationFailed/
        logger.info "Can't connect as user #{initial_ssh_user} to #{ip}, assuming root allowed"
      else
        sleep 2
        logger.info "Failed to connect to #{ip}, retrying"
        retry
      end
    end

    # Restore the original deploy password.
    set(:password, orig_password)
  end

  # Forces a direct connection
  def direct_connection(ip)
    task_name = "_direct_connection_#{ip}_#{rand(1000)}"
    task task_name, :hosts => ip do
      yield
    end

    begin
      send task_name
    rescue ConnectionError => e
      sleep 2
      logger.info "Failed to connect to #{ip}, retrying"
      retry
    end
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
    delim = "## rubber config #{rubber_env.domain} #{Rubber.env}"
    local_hosts = delim + "\n"
    rubber_instances.each do |ic|
      # don't add unqualified hostname in local hosts file since user may be
      # managing multiple domains with same aliases
      hosts_data = [ic.full_name, ic.external_host, ic.internal_host]

      # add the ip aliases for web tools hosts so we can map internal tools
      # to their own vhost to make proxying easier (rewriting url paths for
      # proxy is a real pain, e.g. '/graphite/' externally to '/' on the
      # graphite web app)
      if ic.role_names.include?('web_tools')
        Array(rubber_env.web_tools_proxies).each do |name, settings|
          hosts_data << "#{name}-#{ic.full_name}"
        end
      end

      local_hosts << ic.external_ip << ' ' << hosts_data.join(' ') << "\n"
    end
    local_hosts << delim << "\n"

    # Write out the hosts file for this machine, use sudo
    existing = File.read(hosts_file)
    filtered = existing.gsub(/^#{delim}.*^#{delim}\n?/m, '')

    # only write out if it has changed
    if existing != (filtered + local_hosts)
      logger.info "Writing out aliases into local machines #{hosts_file}, sudo access needed"
      Rubber::Util::sudo_open(hosts_file, 'w') do |f|
        f.write(filtered)
        f.write(local_hosts)
      end
    end
  end


  desc <<-DESC
    Sets up aliases for instance hostnames based on contents of instance.yml.
    Generates /etc/hosts for remote machines and sets hostname on remote instances
  DESC
  task :setup_remote_aliases do
    hosts_file = '/etc/hosts'

    # Generate /etc/hosts contents for the remote instance from instance config
    delim = "## rubber config #{Rubber.env}"
    remote_hosts = []

    rubber_instances.each do |ic|
      hosts_data = [ic.internal_ip, ic.full_name, ic.name, ic.external_host, ic.internal_host]

      # add the ip aliases for web tools hosts so we can map internal tools
      # to their own vhost to make proxying easier (rewriting url paths for
      # proxy is a real pain, e.g. '/graphite/' externally to '/' on the
      # graphite web app)
      if ic.role_names.include?('web_tools')
        Array(rubber_env.web_tools_proxies).each do |name, settings|
          hosts_data << "#{name}-#{ic.full_name}"
        end
      end

      remote_hosts << hosts_data.join(' ')
    end

    if rubber_instances.size > 0

      replace="#{delim}\\n#{remote_hosts.join("\\n")}\\n#{delim}"

      setup_remote_aliases_script = <<-ENDSCRIPT
        sed -i.bak '/#{delim}/,/#{delim}/c #{replace}' /etc/hosts
        if ! grep -q "#{delim}" /etc/hosts; then
          echo -e "#{replace}" >> /etc/hosts
        fi
      ENDSCRIPT

      # If an SSH gateway is being used to deploy to the cluster, we need to ensure that gateway has an updated /etc/hosts
      # first, otherwise it won't be able to resolve the hostnames for the other servers we need to connect to.
      gateway = fetch(:gateway, nil)
      if gateway
        rubber.sudo_script 'setup_remote_aliases', setup_remote_aliases_script, :hosts => gateway
      end

      rubber.sudo_script 'setup_remote_aliases', setup_remote_aliases_script

      # Setup hostname on instance so shell, etcs have nice display
      rsudo "echo $CAPISTRANO:HOST$ > /etc/hostname && hostname $CAPISTRANO:HOST$"

      # Newer ubuntus ec2-init script always resets hostname, so prevent it
      rsudo "mkdir -p /etc/ec2-init && echo compat=0 > /etc/ec2-init/is-compat-env"
    end

    # TODO
    # /etc/resolv.conf to add search domain
    # ~/.ssh/options to setup user/host/key aliases
  end

  desc <<-DESC
    Sets up aliases in dynamic dns provider for instance hostnames based on contents of instance.yml.
  DESC
  required_task :setup_dns_aliases do
    rubber_instances.each do |ic|
      update_dyndns(ic)
    end
  end

  def record_key(record)
    "#{record[:host]}.#{record[:domain]} #{record[:type]}"
  end

  def convert_to_new_dns_format(records)
    record = {}
    records.each do |r|
      record[:host] ||= r[:host]
      record[:domain] ||= r[:domain]
      record[:type] ||= r[:type]
      record[:ttl] ||= r[:ttl] if r[:ttl]
      record[:data] ||= []
      case r[:data]
        when nil then ;
        when Array then record[:data].concat(r[:data])
        else
          record[:data] << r[:data]
      end
    end
    return record
  end

  desc <<-DESC
    Sets up the additional dns records supplied in the dns_records config in rubber.yml
  DESC
  required_task :setup_dns_records do
    records = rubber_env.dns_records
    if records && rubber_env.dns_provider

      provider_name = rubber_env.dns_provider
      provider = Rubber::Dns::get_provider(provider_name, rubber_env)

      # records in rubber_env.dns_records can either have a value which
      # is an array, or multiple equivalent (same host+type)items with
      # value being a string, so try and normalize them
      rubber_records = {}
      records.each do |record|
        record = Rubber::Util.symbolize_keys(record)
        record = provider.setup_opts(record) # assign defaults        
        key = record_key(record)
        rubber_records[key] ||= []
        rubber_records[key] << record
      end
      rubber_records = Hash[rubber_records.collect {|key, records| [key, convert_to_new_dns_format(records)] }]

      provider_records = {}
      domains = rubber_records.values.collect {|r| r[:domain] }.uniq
      precords = domains.collect {|d| provider.find_host_records(:host => '*', :type => '*', :domain => d) }.flatten
      precords.each do |record|
        key = record_key(record)
        raise "unmerged provider records" if provider_records[key]
        provider_records[key] = record
      end

      changes = Hash[(rubber_records.to_a - provider_records.to_a) | (provider_records.to_a - rubber_records.to_a)]

      changes.each do |key, record|
        old_record = provider_records[key]
        new_record = rubber_records[key]
        if old_record && new_record
          # already exists in provider, so modify it
          diff = Hash[(old_record.to_a - new_record.to_a) | (new_record.to_a - old_record.to_a)]
          logger.info "Updating dns record: #{old_record.inspect} changes: #{diff.inspect}"
          provider.update_host_record(old_record, new_record)
        elsif !old_record && new_record
          # doesn't yet exist in provider, so create it
          logger.info "Creating dns record: #{new_record.inspect}"
          provider.create_host_record(new_record)
        elsif old_record && ! new_record
          # ignore these since it shows all the instances created by rubber
          #
          #logger.info "Provider record doesn't exist locally: #{old_record.inspect}"
          #if ENV['FORCE']
          #  destroy_dns_record = ENV['FORCE'] =~ /^(t|y)/
          #else
          #  destroy_dns_record = get_env('DESTROY_DNS', "Destroy DNS record in provider [y/N]?", true)
          #end
          #provider.destroy_host_record(old_record) if destroy_dns_record
        end
      end

    end
  end

  desc <<-DESC
    Exports dns records from your provider into the format readable by rubber in rubber-dns.yml
  DESC
  required_task :export_dns_records do
    if rubber_env.dns_provider

      provider_name = rubber_env.dns_provider
      provider = Rubber::Dns::get_provider(provider_name, rubber_env)

      provider_records = provider.find_host_records(:host => '*', :type => '*', :domain => rubber_env.domain)
      puts({'dns_records' => provider_records.collect {|r| Rubber::Util.stringify_keys(r)}}.to_yaml)
    end
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
    install_core_packages
    install_packages
    install_gems
  end

  desc <<-DESC
    Install core packages that are needed before the general install_packages phase.
  DESC
  task :install_core_packages do
    core_packages = [
        'python-software-properties', # Needed for add-apt-repository, which we use for adding PPAs.
        'bc',                         # Needed for comparing version numbers in bash, which we do for various setup functions.
        'update-notifier-common',     # Needed for notifying us when a package upgrade requires a reboot.
        'scsitools'                   # Needed to rescan SCSI channels for any added devices.
    ]

    rsudo "apt-get -q update"
    rsudo "export DEBIAN_FRONTEND=noninteractive; apt-get -q -o Dpkg::Options::=--force-confold -y --force-yes install #{core_packages.join(' ')}"
  end

  desc <<-DESC
    Install Ubuntu packages. Set 'packages' in rubber.yml to \
    be an array of strings.
  DESC
  task :install_packages do
    package_helper(false)
  end

  desc <<-DESC
    Install ruby gems. Set 'gems' in rubber.yml to \
    be an array of strings.
  DESC
  task :install_gems do
    gem_helper(false)
  end

  desc <<-DESC
    Install ruby gems defined in the rails environment.rb
  DESC
  after "rubber:config", "rubber:install_rails_gems" if (Rubber::Util::is_rails? && !Rubber::Util.is_bundler?)
  task :install_rails_gems do
    rsudo "cd #{current_release} && RAILS_ENV=#{Rubber.env} #{fetch(:rake, 'rake')} gems:install"
  end

  desc <<-DESC
    Convenience task for installing your defined set of ruby gems locally.
  DESC
  required_task :install_local_gems do
    fatal("install_local_gems can only be run in development") if Rubber.env != 'development'
    env = rubber_cfg.environment.bind(rubber_cfg.environment.known_roles)
    gems = env['gems']
    expanded_gem_list = []
    gems.each do |gem_spec|
      if gem_spec.is_a?(Array)
        expanded_gem_list << "#{gem_spec[0]}:#{gem_spec[1]}"
      else
        expanded_gem_list << gem_spec
      end
    end
    expanded_gem_list = expanded_gem_list.join(' ')

    logger.info "Installing gems:#{expanded_gem_list}"
    open("/tmp/gem_helper", "w") {|f| f.write(gem_helper_script)}
    system "ruby /tmp/gem_helper install #{expanded_gem_list}"
  end

  set :gem_sources_helper_script, <<-'ENDSCRIPT'
    sources = ARGV

    installed = []
    `gem sources -l`.each_line do |line|
      line = line.strip
      installed << line if line.size > 0 && line =~ /^[^*]/
    end

    to_install = sources - installed
    to_remove = installed - sources

    if to_install.size > 0
      to_install.each do |source|
        system "gem sources -a #{source}"
        fail "Unable to add gem sources" if $?.exitstatus > 0
      end
    end
    if to_remove.size > 0
      to_remove.each do |source|
        system "gem sources -r #{source}"
        fail "Unable to remove gem sources" if $?.exitstatus > 0
      end
    end
  ENDSCRIPT

  desc <<-DESC
    Setup ruby gems sources. Set 'gemsources' in rubber.yml to \
    be an array of URI strings.
  DESC
  task :setup_gem_sources do
    if rubber_env.gemsources
      script = prepare_script 'gem_sources_helper', gem_sources_helper_script, nil
      rsudo "ruby #{script} #{rubber_env.gemsources.join(' ')}"
    end
  end

  desc <<-DESC
    The ubuntu has /bin/sh linking to dash instead of bash, fix this
    You can override this task if you don't want this to happen
  DESC
  task :link_bash do
    rsudo "ln -sf /bin/bash /bin/sh"
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
    rsudo "echo $CAPISTRANO:VAR$ > /etc/timezone", opts
    rsudo "ln -sf /usr/share/zoneinfo/$CAPISTRANO:VAR$ /etc/localtime", opts
    # restart syslog so that times match timezone
    sudo_script 'restart_syslog', <<-ENDSCRIPT
      if [[ -x /etc/init.d/sysklogd ]]; then
        /etc/init.d/sysklogd restart
      elif [[ -x /etc/init.d/rsyslog ]]; then
        service rsyslog restart
     fi
    ENDSCRIPT
  end

  desc <<-DESC
    Enable the ubuntu multiverse source for getting packages like
    ec2-ami-tools used for bundling images
  DESC
  task :enable_multiverse do
    sudo_script 'enable_multiverse', <<-ENDSCRIPT
      if ! grep -qc multiverse /etc/apt/sources.list /etc/apt/sources.list.d/* &> /dev/null; then
        cat /etc/apt/sources.list | sed 's/main universe/multiverse/' > /etc/apt/sources.list.d/rubber-multiverse-source.list
      elif grep -q multiverse /etc/apt/sources.list &> /dev/null; then
        cat /etc/apt/sources.list | sed -n '/multiverse$/s/^#\s*//p' > /etc/apt/sources.list.d/rubber-multiverse-source.list
      fi
    ENDSCRIPT
  end

  def update_dyndns(instance_item)
    env = rubber_cfg.environment.bind(instance_item.role_names, instance_item.name)
    if env.dns_provider
      provider = Rubber::Dns::get_provider(env.dns_provider, env)
      provider.update(instance_item.name, instance_item.external_ip)

      # add the ip aliases for web tools hosts so we can map internal tools
      # to their own vhost to make proxying easier (rewriting url paths for
      # proxy is a real pain, e.g. '/graphite/' externally to '/' on the
      # graphite web app)
      if instance_item.role_names.include?('web_tools')
        Array(rubber_env.web_tools_proxies).each do |name, settings|
          name = name.gsub('_', '-')
          provider.update("#{name}-#{instance_item.name}", instance_item.external_ip)
        end
      end
    end
  end

  def destroy_dyndns(instance_item)
    env = rubber_cfg.environment.bind(instance_item.role_names, instance_item.name)
    if env.dns_provider
      provider = Rubber::Dns::get_provider(env.dns_provider, env)
      provider.destroy(instance_item.name)

      # add the ip aliases for web tools hosts so we can map internal tools
      # to their own vhost to make proxying easier (rewriting url paths for
      # proxy is a real pain, e.g. '/graphite/' externally to '/' on the
      # graphite web app)
      if instance_item.role_names.include?('web_tools')
        Array(rubber_env.web_tools_proxies).each do |name, settings|
          provider.destroy("#{name}-#{instance_item.name}")
        end
      end
    end
  end

  def package_helper(upgrade=false)
    opts = get_host_options('packages') do |pkg_list|
      expanded_pkg_list = []
      pkg_list.each do |pkg_spec|
        if pkg_spec.is_a?(Array)
          expanded_pkg_list << "#{pkg_spec[0]}=#{pkg_spec[1]}"
        else
          expanded_pkg_list << pkg_spec
        end
      end
      expanded_pkg_list << 'ec2-ami-tools' if rubber_env.cloud_provider == 'aws'
      expanded_pkg_list.join(' ')
    end

    rsudo "apt-get -q update"
    if upgrade
      if ENV['NO_DIST_UPGRADE']
        rsudo "export DEBIAN_FRONTEND=noninteractive; apt-get -q -o Dpkg::Options::=--force-confold -y --force-yes upgrade"
      else
        rsudo "export DEBIAN_FRONTEND=noninteractive; apt-get -q -o Dpkg::Options::=--force-confold -y --force-yes dist-upgrade"
      end
    else
      rsudo "export DEBIAN_FRONTEND=noninteractive; apt-get -q -o Dpkg::Options::=--force-confold -y --force-yes install $CAPISTRANO:VAR$", opts
    end

    maybe_reboot
  end

  def multi_capture(cmd, opts={})
    mutex = Mutex.new
    host_data = {}
    run(cmd, opts) do |channel, stream, data|
      if data
        host = channel.properties[:host]
        mutex.synchronize do
          host_data[host] ||= ""
          host_data[host] << data
        end
      end
    end
    return host_data
  end

  def maybe_reboot
    reboot_needed = multi_capture("echo $(ls /var/run/reboot-required 2> /dev/null)")
    reboot_hosts = reboot_needed.collect {|k, v| v.strip.size > 0 ? k : nil}.compact.sort

    # Figure out which hosts are bootstrapping for the first time so we can auto reboot
    # If there is no deployed app directory, then we have never bootstrapped. 
    auto_reboot = multi_capture("echo $(ls #{deploy_to} 2> /dev/null)")
    auto_reboot_hosts = auto_reboot.collect {|k, v| v.strip.size == 0 ? k : nil}.compact.sort

    if reboot_hosts.size > 0

      # automatically reboot if FORCE or if all the hosts that need rebooting
      # are bootstrapping for the first time
      if ENV['FORCE'] =~ /^(t|y)/ || reboot_hosts == auto_reboot_hosts
        ENV['REBOOT'] = 'y'
        logger.info "Updates require a reboot on hosts #{reboot_hosts.inspect}"
      end

      reboot = get_env('REBOOT', "Updates require a reboot on hosts #{reboot_hosts.inspect}, reboot [y/N]?", false)
      ENV['REBOOT'] = reboot # `get_env` chomps the REBOOT value of the env, so reset it here so the value is retained across multiple calls.

      reboot = (reboot =~ /^y/)

      if reboot

        logger.info "Rebooting ..."
        begin
          run("#{sudo} reboot", :hosts => reboot_hosts)
          # since we rebooted, teardown the connections to force cap to reconnect
          teardown_connections_to(sessions.keys)
        rescue
          # swallow exception since there is a chance
          # net:ssh throws an Exception
        end

        sleep 30

        reboot_hosts.each do |host|
          direct_connection(host) do
            run "echo"
          end
          logger.info "#{host} completed reboot"
        end

      end

      # could take a while to reboot (or get answer from prompt), so
      # we need to rebuild all capistrano connections in case they timed out
      teardown_connections_to(sessions.keys)

    end
  end

  def custom_package(url_base, name, ver, install_test)
    rubber.sudo_script "install_#{name}", <<-ENDSCRIPT
      if [[ #{install_test} ]]; then
        arch=`uname -m`
        if [ "$arch" = "x86_64" ]; then
          src="#{url_base}/#{name}_#{ver}_amd64.deb"
        else
          src="#{url_base}/#{name}_#{ver}_i386.deb"
        fi
        src_file="${src##*/}"
        wget -qNP /tmp ${src}
        dpkg -i /tmp/${src_file}
      fi
    ENDSCRIPT
  end

  def handle_gem_prompt(ch, data, str)
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

  # Rubygems always installs even if the gem is already installed
  # When providing versions, rubygems fails unless versions are provided for all gems
  # This helper script works around these issues by installing gems only if they
  # aren't already installed, and separates versioned/unversioned into two separate
  # calls to rubygems
  #
  set :gem_helper_script, <<-'ENDSCRIPT'
    gem_cmd = ARGV[0]
    gems = ARGV[1..-1]
    cmd = "gem #{gem_cmd} --no-rdoc --no-ri"

    to_install = {}
    to_install_ver = {}
    # gem list passed in, possibly with versions, as "gem1 gem2:1.2 gem3"
    gems.each do |gem_spec|
      parts = gem_spec.split(':')
      if parts[1]
        to_install_ver[parts[0]] = parts[1]
      else
        to_install[parts[0]] = true
      end
    end

    installed = {}
    `gem list --local`.each_line do |line|
        parts = line.scan(/(.*) \((.*)\)/).first
        next unless parts && parts.size == 2
        installed[parts[0]] = parts[1].split(",")
    end

    to_install.delete_if {|g, v| installed.has_key?(g) } if gem_cmd == 'install'
    to_install_ver.delete_if {|g, v| installed.has_key?(g) && installed[g].include?(v) }

    # rubygems can only do asingle versioned gem at a time so we need
    # to do the two groups separately
    # install versioned ones first so unversioned don't pull in a newer version
    to_install_ver.each do |g, v|
      system "#{cmd} #{g} -v #{v}"
      fail "Unable to install versioned gem #{g}:#{v}" if $?.exitstatus > 0
    end
    if to_install.size > 0
      gem_list = to_install.keys.join(' ')
      system "#{cmd} #{gem_list}"
      fail "Unable to install gems" if $?.exitstatus > 0
    end
  ENDSCRIPT

  # Helper for installing gems,allows one to respond to prompts
  def gem_helper(update=false)
    cmd = update ? "update" : "install"

    opts = get_host_options('gems') do |gem_list|
      expanded_gem_list = []
      gem_list.each do |gem_spec|
        if gem_spec.is_a?(Array)
          expanded_gem_list << "#{gem_spec[0]}:#{gem_spec[1]}"
        else
          expanded_gem_list << gem_spec
        end
      end
      expanded_gem_list.join(' ')
    end

    if opts.size > 0
      script = prepare_script('gem_helper', gem_helper_script, nil)
      rsudo "ruby #{script} #{cmd} $CAPISTRANO:VAR$", opts do |ch, str, data|
        handle_gem_prompt(ch, data, str)
      end
    end
  end

end
