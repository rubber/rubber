namespace :rubber do

  desc <<-DESC
    Sets up persistent volumes in the cloud
    All volumes defined in rubber.yml will be created if neccessary, and attached/mounted on their associated instances
  DESC
  required_task :setup_volumes do
    rubber_instances.filtered.each do |ic|
      env = rubber_cfg.environment.bind(ic.role_names, ic.name)
      created_vols = []
      vol_specs = env.volumes || []
      vol_specs.each do |vol_spec|
        created_vols << setup_volume(ic, vol_spec)
      end
      created_vols.compact!

      created_parts = []
      partition_specs = env.local_volumes || []
      partition_specs.each do |partition_spec|
        created_parts << setup_partition(ic, partition_spec)
      end
      created_parts.compact!
      zero_partitions(ic, created_parts)
      created_vols += created_parts
      
      created_vols = created_vols.compact.uniq
      raid_specs = env.raid_volumes || []
      raid_specs.each do |raid_spec|
        # we want to format if we created the ec2 volumes, or if we don't have any
        # ec2 volumes and are just creating raid array from ephemeral stores
        format = raid_spec['source_devices'].all? {|dev| created_vols.include?(dev)}
        setup_raid_volume(ic, raid_spec, format)
      end
    end
  end

  desc <<-DESC
    Shows the configured persistent volumes
  DESC
  required_task :describe_volumes do
    results = []
    format = "%-20s %-15s %-15s %-20s"
    results << format % %w[Id Status Attached Instance]

    volumes = cloud.describe_volumes()
    volumes.each do |volume|
      results << format % [volume[:id], volume[:status], volume[:attachment_status], volume[:attachment_instance_id]]
    end

    results.each {|r| logger.info r}
  end

  desc <<-DESC
    Shows the configured persistent volumes
  DESC
  required_task :destroy_volume do
    volume_id = get_env('VOLUME_ID', "Volume ID", true)
    destroy_volume(volume_id)
  end

  def create_volume(size, zone)
    volumeId = cloud.create_volume(size.to_s, zone)
    fatal "Failed to create volume" if volumeId.nil?
    return volumeId
  end

  def attach_volume(vol_id, instance_id, device)
    cloud.attach_volume(vol_id, instance_id, device)
  end

  def setup_volume(ic, vol_spec)
    created = nil
    key = "#{ic.name}_#{vol_spec['device']}"
    artifacts = rubber_instances.artifacts
    vol_id = artifacts['volumes'][key]

    # first create the volume if we don't have a global record (artifacts) for it
    if ! vol_id
      logger.info "Creating volume for #{ic.full_name}:#{vol_spec['device']}"
      vol_id = create_volume(vol_spec['size'], vol_spec['zone'])
      artifacts['volumes'][key] = vol_id
      rubber_instances.save
      created = vol_spec['device']
    end

    # then, attach it if we don't have a record (on instance) of attachment
    ic.volumes ||= []
    if ! ic.volumes.include?(vol_id)
      logger.info "Attaching volume #{vol_id} to #{ic.full_name}:#{vol_spec['device']}"
      attach_volume(vol_id, ic.instance_id, vol_spec['device'])
      ic.volumes << vol_id
      rubber_instances.save

      print "Waiting for volume to attach"
      while true do
        print "."
        sleep 2
        volume = cloud.describe_volumes(vol_id).first
        break if volume[:attachment_status] == "attached"
      end
      print "\n"

      # we don't mount/format at this time if we are doing a RAID array
      if vol_spec['mount'] && vol_spec['filesystem']
        # then format/mount/etc if we don't have an entry in hosts file
        task :_setup_volume, :hosts => ic.external_ip do
          rubber.sudo_script 'setup_volume', <<-ENDSCRIPT
            if ! grep -q '#{vol_spec['mount']}' /etc/fstab; then
              if mount | grep -q '#{vol_spec['mount']}'; then
                umount '#{vol_spec['mount']}'
              fi
              mv /etc/fstab /etc/fstab.bak
              cat /etc/fstab.bak | grep -v '#{vol_spec['mount']}' > /etc/fstab
              echo '#{vol_spec['device']} #{vol_spec['mount']} #{vol_spec['filesystem']} noatime 0 0 # rubber volume #{vol_id}' >> /etc/fstab

              #{('yes | mkfs -t ' + vol_spec['filesystem'] + ' ' + vol_spec['device']) if created}
              mkdir -p '#{vol_spec['mount']}'
              mount '#{vol_spec['mount']}'
            fi
          ENDSCRIPT
        end
        _setup_volume
      end

    end
    return created
  end

  def setup_partition(ic, partition_spec)
    created = nil
    part_id = partition_spec['partition_device']

    # Only create the partition if we haven't already done so
    ic.partitions ||= []
    if ! ic.partitions.include?(part_id)
      # then format/mount/etc if we don't have an entry in hosts file
      task :_setup_partition, :hosts => ic.external_ip do
        rubber.sudo_script 'setup_partition', <<-ENDSCRIPT
          if ! fdisk -l 2>&1 | grep -q '#{partition_spec['partition_device']}'; then
            if grep -q '#{partition_spec['disk_device']}\\b' /etc/fstab; then
              umount #{partition_spec['disk_device']}
              mv /etc/fstab /etc/fstab.bak
              cat /etc/fstab.bak | grep -v '#{partition_spec['disk_device']}\\b' > /etc/fstab
            fi

            # partition format is: Start (blank is first available),Size(MB due to -uM),Id(83=linux,82=swap,etc),Bootable
            echo "#{partition_spec['start']},#{partition_spec['size']},#{partition_spec['type']},#{partition_spec['bootable']}" | sfdisk -L -uM #{partition_spec['disk_device']}
          fi
        ENDSCRIPT
      end
      _setup_partition

      ic.partitions << part_id
      rubber_instances.save
      created = part_id

    end

    return created
  end

  def zero_partitions(ic, partitions)
    env = rubber_cfg.environment.bind(ic.role_names, ic.name)

    # don't zero out the ones that we weren't told to
    partitions.delete_if do |part|
      spec = env.local_volumes.find {|s| s['partition_device'] == part}
      ! spec['zero']
    end

    if partitions.size > 0
      zero_script = ""
      partitions.each do |partition|
        zero_script << "nohup dd if=/dev/zero bs=1M of=#{partition} &> /dev/null &\n"
      end
      # then format/mount/etc if we don't have an entry in hosts file
      task :_zero_partitions, :hosts => ic.external_ip do
        rubber.sudo_script 'zero_partitions', <<-ENDSCRIPT
          # zero out parition for performance (see amazon DevGuide)
          echo "Zeroing out raid partitions to improve performance, this way take a while"
          #{zero_script}

          echo "Waiting for partitions to zero out"
          while true; do
            if ! ps ax | grep -q "[d]d.*/dev/zero"; then exit; fi
            echo -n .
            sleep 1
          done
        ENDSCRIPT
      end
      _zero_partitions
    end
  end

  def setup_raid_volume(ic, raid_spec, create=false)
    if create
      mdadm_init = "mdadm --create #{raid_spec['device']} --level #{raid_spec['raid_level']} --raid-devices #{raid_spec['source_devices'].size} #{raid_spec['source_devices'].sort.join(' ')}"
    else
      mdadm_init = "mdadm --assemble #{raid_spec['device']} #{raid_spec['source_devices'].sort.join(' ')}"
    end

    task :_setup_raid_volume, :hosts => ic.external_ip do
      rubber.sudo_script 'setup_raid_volume', <<-ENDSCRIPT
        if ! grep -q '#{raid_spec['device']}' /etc/fstab; then
          if mount | grep -q '#{raid_spec['mount']}'; then
            umount '#{raid_spec['mount']}'
          fi
          mv /etc/fstab /etc/fstab.bak
          cat /etc/fstab.bak | grep -v '#{raid_spec['mount']}' > /etc/fstab
          echo '#{raid_spec['device']} #{raid_spec['mount']} #{raid_spec['filesystem']} noatime 0 0 # rubber raid volume' >> /etc/fstab

          # seems to help devices initialize, otherwise mdadm fails because
          # device not ready even though ec2 says the volume is attached
          fdisk -l &> /dev/null

          #{mdadm_init}

          # set reconstruction speed
          echo $((30*1024)) > /proc/sys/dev/raid/speed_limit_min

          echo 'DEVICE /dev/hd*[0-9] /dev/sd*[0-9]' > /etc/mdadm/mdadm.conf
          mdadm --detail --scan >> /etc/mdadm/mdadm.conf

          mv /etc/rc.local /etc/rc.local.bak
          echo "mdadm --assemble --scan" > /etc/rc.local
          chmod +x /etc/rc.local

          #{('yes | mkfs -t ' + raid_spec['filesystem'] + ' ' + raid_spec['device']) if create}
          mkdir -p '#{raid_spec['mount']}'
          mount '#{raid_spec['mount']}'
        fi
      ENDSCRIPT
    end
    _setup_raid_volume
  end

  def destroy_volume(volume_id)

    logger.info "Detaching volume #{volume_id}"
    cloud.detach_volume(volume_id) rescue logger.info("Volume was not attached")

    print "Waiting for volume to detach"
    while true do
      print "."
      sleep 2
      volume = cloud.describe_volumes(volume_id).first
      status = volume && volume[:attachment_status]
      break if !status || status == "detached"
    end
    print "\n"

    logger.info "Deleting volume #{volume_id}"
    cloud.destroy_volume(volume_id)

    logger.info "Removing volume #{volume_id} from rubber instances file"
    artifacts = rubber_instances.artifacts
    artifacts['volumes'].delete_if {|k,v| v == volume_id}
    rubber_instances.each do |ic|
      ic.volumes.delete(volume_id) if ic.volumes
    end
    rubber_instances.save
  end
  
end
