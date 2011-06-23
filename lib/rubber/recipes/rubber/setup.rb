require "bundler/capistrano" if Rubber::Util.is_bundler?

namespace :rubber do

  desc <<-DESC
    Bootstraps instances by setting timezone, installing packages and gems
  DESC
  task :bootstrap do
    link_bash
    set_timezone
    enable_multiverse
    upgrade_packages
    install_packages
    setup_volumes
    setup_gem_sources
    install_gems
    deploy.setup
  end

  # Sets up instance to allow root access (e.g. recent canonical AMIs)
  def enable_root_ssh(ip, initial_ssh_user)

    task :_allow_root_ssh, :hosts => "#{initial_ssh_user}@#{ip}" do
      rsudo "cp /home/#{initial_ssh_user}/.ssh/authorized_keys /root/.ssh/"
    end

    begin
      _allow_root_ssh
    rescue ConnectionError => e
      if e.message =~ /Net::SSH::AuthenticationFailed/
        logger.info "Can't connect as user #{initial_ssh_user} to #{ip}, assuming root allowed"
      else
        sleep 2
        logger.info "Failed to connect to #{ip}, retrying"
        retry
      end
    end
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
    delim = "## rubber config #{rubber_env.domain} #{RUBBER_ENV}"
    local_hosts = delim + "\n"
    rubber_instances.each do |ic|
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
    rubber_instances.each do |ic|
      update_dyndns(ic)
    end
  end

  desc <<-DESC
    Sets up the additional dns records supplied in the dns_records config in rubber.yml
  DESC
  required_task :setup_dns_records do
    records = rubber_env.dns_records
    if records && rubber_env.dns_provider
      provider = Rubber::Dns::get_provider(rubber_env.dns_provider, rubber_env)

      # collect the round robin records (those with the same host/domain/type)
      rr_records = []
      records.each_with_index do |record, i|
        m = records.find_all {|r| record['host'] == r['host'] && record['domain'] == r['domain'] && record['type'] == r['type']}
        m = m.sort {|a,b| a.object_id <=> b.object_id}
        rr_records << m if m.size > 1 && ! rr_records.include?(m)
      end

      # simple records are those that aren't round robin ones
      simple_records = records - rr_records.flatten
      
      # for each simple record, create or update as necessary
      simple_records.each do |record|
        matching = provider.find_host_records(:host => record['host'], :domain =>record['domain'], :type => record['type'])
        if matching.size > 1
          msg =  "Multiple records in dns provider, but not in rubber.yml\n"
          msg << "Round robin records need to be in both, or neither.\n"
          msg << "Please fix manually:\n"
          msg << matching.pretty_inspect
          fatal(msg)
        end

        record = provider.setup_opts(record)
        if matching.size == 1
          match = matching.first
          if  provider.host_records_equal?(record, match)
            logger.info "Simple dns record already up to date: #{record[:host]}.#{record[:domain]}:#{record[:type]} => #{record[:data]}"
          else
            logger.info "Updating simple dns record: #{record[:host]}.#{record[:domain]}:#{record[:type]} => #{record[:data]}"
            provider.update_host_record(match, record)
          end
        else
          logger.info "Creating simple dns record: #{record[:host]}.#{record[:domain]}:#{record[:type]} => #{record[:data]}"
          provider.create_host_record(record)
        end
      end

      # group round robin records
      rr_records.each do |rr_group|
        host = rr_group.first['host']
        domain = rr_group.first['domain']
        type = rr_group.first['type']
        matching = provider.find_host_records(:host => host, :domain => domain, :type => type)

        # remove from consideration the local records that are the same as remote ones
        matching.clone.each do |r|
          rr_group.delete_if {|rg| provider.host_records_equal?(r, rg) }
          matching.delete_if {|rg| provider.host_records_equal?(r, rg) }
        end
        if rr_group.size == 0 && matching.size == 0
          logger.info "Round robin dns records already up to date: #{host}.#{domain}:#{type}"
        end

        # create the local records that don't exist remotely
        rr_group.each do |r|
          r = provider.setup_opts(r)
          logger.info "Creating round robin dns record: #{r[:host]}.#{r[:domain]}:#{r[:type]} => #{r[:data]}"
          provider.create_host_record(r)
        end
        
        # remove the remote records that don't exist locally
        matching.each do |r|
          logger.info "Removing round robin dns record: #{r[:host]}.#{r[:domain]}:#{r[:type]} => #{r[:data]}"
          provider.destroy_host_record(r)
        end
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
    delim = "## rubber config"
    delim = "#{delim} #{RUBBER_ENV}"
    remote_hosts = delim + "\n"
    rubber_instances.each do |ic|
      hosts_data = [ic.full_name, ic.name, ic.external_host, ic.internal_host].join(' ')
      remote_hosts << ic.internal_ip << ' ' << hosts_data << "\n"
    end
    remote_hosts << delim << "\n"
    if rubber_instances.size > 0
      # write out the hosts file for the remote instances
      # NOTE that we use "capture" to get the existing hosts
      # file, which only grabs the hosts file from the first host
      filtered = (capture "cat #{hosts_file}").gsub(/^#{delim}.*^#{delim}\n?/m, '')
      filtered = filtered + remote_hosts
      # Put the generated hosts back on remote instance
      put filtered, hosts_file

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
  after "rubber:config", "rubber:install_rails_gems" if (Rubber::Util::is_rails2? && !Rubber::Util.is_bundler?)
  task :install_rails_gems do
    rsudo "cd #{current_release} && RAILS_ENV=#{RUBBER_ENV} rake gems:install"
  end

  desc <<-DESC
    Convenience task for installing your defined set of ruby gems locally.
  DESC
  required_task :install_local_gems do
    fatal("install_local_gems can only be run in development") if RUBBER_ENV != 'development'
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
    rsudo "cp /usr/share/zoneinfo/$CAPISTRANO:VAR$ /etc/localtime", opts
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
    end
  end

  def destroy_dyndns(instance_item)
    env = rubber_cfg.environment.bind(instance_item.role_names, instance_item.name)
    if env.dns_provider
      provider = Rubber::Dns::get_provider(env.dns_provider, env)
      provider.destroy(instance_item.name)
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
      expanded_pkg_list.join(' ')
    end

    rsudo "apt-get -q update"
    if upgrade
      rsudo "export DEBIAN_FRONTEND=noninteractive; apt-get -q -o Dpkg::Options::=--force-confold -y --force-yes dist-upgrade"
    else
      rsudo "export DEBIAN_FRONTEND=noninteractive; apt-get -q -o Dpkg::Options::=--force-confold -y --force-yes install $CAPISTRANO:VAR$", opts
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
