namespace :rubber do

  desc <<-DESC
    Bootstraps instances by setting timezone, installing packages and gems
  DESC
  task :bootstrap do
    set_timezone
    link_bash
    install_packages
    setup_volumes
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
    delim = "## rubber config #{env.domain} #{RUBBER_ENV}"
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

    # Generate /etc/hosts contents for the remote instance from instance config
    delim = "## rubber config"
    delim = "#{delim} #{RUBBER_ENV}"
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

    sudo "apt-get -q update"
    if upgrade
      sudo "/bin/sh -c 'export DEBIAN_FRONTEND=noninteractive; apt-get -q -y --force-yes dist-upgrade'"
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

  # Helper for installing gems,allows one to respond to prompts
  def gem_helper(update=false)
    cmd = update ? "update" : "install"

    # when versions are provided for a gem, rubygems fails unless versions ae provided for all gems
    #
    # first do the gems that the user specified versions for
    opts = get_host_options('gems') do |gem_list|
      expanded_gem_list = []
      gem_list.each do |gem_spec|
        if gem_spec.is_a?(Array)
          expanded_gem_list << "#{gem_spec[0]} -v #{gem_spec[1]}"
        end
      end
      expanded_gem_list.join(' ')
    end
    if opts.size > 0
      sudo "gem #{cmd} $CAPISTRANO:VAR$ --no-rdoc --no-ri", opts do |ch, str, data|
        handle_gem_prompt(ch, data, str)
      end
    end

    # then do the gems without versions
    opts = get_host_options('gems') do |gem_list|
      expanded_gem_list = []
      gem_list.each do |gem_spec|
        if ! gem_spec.is_a?(Array)
          expanded_gem_list << gem_spec
        end
      end
      expanded_gem_list.join(' ')
    end
    if opts.size > 0
      sudo "gem #{cmd} $CAPISTRANO:VAR$ --no-rdoc --no-ri", opts do |ch, str, data|
        handle_gem_prompt(ch, data, str)
      end
    end
  end

end