namespace :rubber do

  desc <<-DESC
    Sets up persistent volumes in the cloud
    All volumes defined in rubber.yml will be created if necessary, and attached/mounted on their associated instances
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
      raid_volume_list = raid_specs.collect {|vol| vol["source_devices"]}.join(" ")
      raid_specs.each do |raid_spec|
        # we want to format if we created the ec2 volumes, or if we don't have any
        # ec2 volumes and are just creating raid array from ephemeral stores
        format = raid_spec['source_devices'].all? {|dev| created_vols.include?(dev.gsub("xv","s"))}
        setup_raid_volume(ic, raid_spec, format, raid_volume_list)
      end

      lvm_volume_group_specs = env.lvm_volume_groups || []
      lvm_volume_group_specs.each do |lvm_volume_group_spec|
        setup_lvm_group(ic, lvm_volume_group_spec)
      end
    end

    # The act of setting up volumes might blow away previously deployed code, so reset the update state so it can
    # be deployed again if needed.
    deploy_to = fetch(:deploy_to, nil)

    unless deploy_to.nil?
      deployed = capture("echo $(ls /var/run/reboot-required 2> /dev/null)")

      unless deployed
        set :rubber_code_was_updated, false
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
    Destroys the configured persistent volumes
  DESC
  required_task :destroy_volume do
    volume_id = get_env('VOLUME_ID', "Volume ID", true)
    destroy_volume(volume_id)
  end

  desc <<-DESC
    Detaches the configured persistent volumes
  DESC
  required_task :detach_volume do
    volume_id = get_env('VOLUME_ID', "Volume ID", true)
    detach_volume(volume_id)
  end

  def setup_volume(ic, vol_spec)
    created = nil
    key = "#{ic.name}_#{vol_spec['device']}"
    artifacts = rubber_instances.artifacts
    vol_id = artifacts['volumes'][key]

    cloud.before_create_volume(ic, vol_spec)

    # first create the volume if we don't have a global record (artifacts) for it
    if ! vol_id
      logger.info "Creating volume for #{ic.full_name}:#{vol_spec['device']}"
      vol_id = cloud.create_volume(ic, vol_spec)
      artifacts['volumes'][key] = vol_id
      rubber_instances.save
      created = vol_spec['device']
    end

    # then, attach it if we don't have a record (on instance) of attachment
    ic.volumes ||= []
    if ! ic.volumes.include?(vol_id)
      logger.info "Attaching volume #{vol_id} to #{ic.full_name}:#{vol_spec['device']}"
      cloud.after_create_volume(ic, vol_id, vol_spec)
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
            # Make sure the newly added volume was found.
            rescan-scsi-bus || true

            if ! grep -q '#{vol_spec['mount']}' /etc/fstab; then
              if mount | grep -q '#{vol_spec['mount']}'; then
                umount '#{vol_spec['mount']}'
              fi
              mv /etc/fstab /etc/fstab.bak
              cat /etc/fstab.bak | grep -v '#{vol_spec['mount']}' > /etc/fstab
              if [[ #{rubber_env.cloud_provider == 'aws'} == true ]] && [[ `lsb_release -r -s | sed 's/[.].*//'` -gt "10" ]]; then
		            device=`echo #{vol_spec['device']} | sed 's/sd/xvd/'`
	            else
		            device='#{vol_spec['device']}'
	            fi
		 
		          echo "$device #{vol_spec['mount']} #{vol_spec['filesystem']} #{vol_spec['mount_opts'] ? vol_spec['mount_opts'] : 'noatime'} 0 0 # rubber volume #{vol_id}" >> /etc/fstab
		          
		          # Ensure volume is ready before running mkfs on it.
		          echo 'Waiting for device'
              cnt=0
              while ! [[ -b $device ]]; do
                if [[ "$cnt" -eq "15" ]]; then
                  echo 'Timed out waiting for EBS device to be ready.'
                  mv /etc/fstab.bak /etc/fstab
                  exit 1
                fi
                echo '.'
                sleep 2
                let "cnt = $cnt + 1"
              done
              echo 'Device ready'

              #{('yes | mkfs -t ' + vol_spec['filesystem'] + ' ' + '$device') if created}
              #{("mkdir -p '#{vol_spec['mount']}'") if vol_spec['mount']}
              #{("mount '#{vol_spec['mount']}'") if vol_spec['mount']}
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
    partitions = partitions.clone

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
          echo "Zeroing out raid partitions to improve performance, this may take a while"
          #{zero_script}
          bg_pid=$!
          sleep 1

          echo "Waiting for partitions to zero out"
          while kill -0 $bg_pid &> /dev/null; do
            echo -n .
            sleep 5
          done
          
          # this returns exit code even if pid has already died, and thus triggers fail fast shell error
          wait $bg_pid
        ENDSCRIPT
      end
      _zero_partitions
    end
  end

  def setup_raid_volume(ic, raid_spec, create=false, raid_volume_list=nil)
    if create
      mdadm_init = "yes | mdadm --create #{raid_spec['device']} --metadata=1.1 --level #{raid_spec['raid_level']} --raid-devices #{raid_spec['source_devices'].size} #{raid_spec['source_devices'].sort.join(' ')}"
    else
      mdadm_init = "yes | mdadm --assemble #{raid_spec['device']} #{raid_spec['source_devices'].sort.join(' ')}"
    end
    
    task :_setup_raid_volume, :hosts => ic.external_ip do
      rubber.sudo_script 'setup_raid_volume', <<-ENDSCRIPT
        if ! grep -qE '#{raid_spec['device']}|#{raid_spec['mount']}' /etc/fstab; then
          if mount | grep -q '#{raid_spec['mount']}'; then
            umount '#{raid_spec['mount']}'
          fi
          
          # wait for devices to initialize, otherwise mdadm fails because
          # device not ready even though ec2 says the volume is attached
          echo 'Waiting for devices'
          cnt=0
          while ! [[ -b #{raid_spec['source_devices'] * " && -b "} ]]; do
            if [[ "$cnt" -eq "15" ]]; then
              echo 'Timed out waiting for EBS volumes to initialize.'
              exit 1
            fi
            echo '.'
            sleep 2
            let "cnt = $cnt + 1"
          done
          echo 'Devices ready'

          udevadm control --stop-exec-queue
          #{mdadm_init}
          udevadm control --start-exec-queue

          # set reconstruction speed
          echo $((30*1024)) > /proc/sys/dev/raid/speed_limit_min

          echo 'MAILADDR #{rubber_env.admin_email}' > /etc/mdadm/mdadm.conf
          echo 'DEVICE #{raid_volume_list}' >> /etc/mdadm/mdadm.conf
          mdadm --detail --scan | sed s/name=.*\\ // >> /etc/mdadm/mdadm.conf
          
          update-initramfs -u

          mv /etc/rc.local /etc/rc.local.bak
          echo "mdadm --assemble --scan" > /etc/rc.local
          chmod +x /etc/rc.local
          
          mv /etc/fstab /etc/fstab.bak
          cat /etc/fstab.bak | grep -vE '#{raid_spec['device']}|#{raid_spec['mount']}' > /etc/fstab
          echo '#{raid_spec['device']} #{raid_spec['mount']} #{raid_spec['filesystem']} #{raid_spec['mount_opts'] ? raid_spec['mount_opts'] : 'noatime'} 0 0 # rubber raid volume' >> /etc/fstab

          #{('yes | mkfs -t ' + raid_spec['filesystem'] + ' ' + raid_spec['filesystem_opts'] + ' ' + raid_spec['device']) if create}
          mkdir -p '#{raid_spec['mount']}'
          mount '#{raid_spec['mount']}'
                 
        fi
      ENDSCRIPT
    end
    _setup_raid_volume
  end

  def setup_lvm_group(ic, lvm_volume_group_spec)
    physical_volumes = lvm_volume_group_spec['physical_volumes'].kind_of?(Array) ? lvm_volume_group_spec['physical_volumes'] : [lvm_volume_group_spec['physical_volumes']]
    volume_group_name = lvm_volume_group_spec['name']
    extent_size = lvm_volume_group_spec['extent_size'] || 32

    volumes = lvm_volume_group_spec['volumes'] || []

    def create_logical_volume_in_bash(volume, volume_group_name)
      device_name = "/dev/#{volume_group_name}/#{volume['name']}"

      resize_command =
          case volume['filesystem']
            when 'xfs'
              "xfs_growfs '#{volume['mount']}'"
            when 'reiserfs'
              "resize_reiserfs -f #{device_name}"
            when 'jfs'
              "mount -o remount,resize #{volume['mount']}"
            when /^ext/
              <<-RESIZE_COMMAND
              umount #{device_name}
              ext2resize #{device_name}
              mount #{volume['mount']}
              RESIZE_COMMAND
            else
              raise "Do not know how to resize filesystem '#{volume['filesystem']}'"
          end

      <<-ENDSCRIPT
        # Add the logical volume mount point to /etc/fstab.
        if ! grep -q '#{volume['name']}' /etc/fstab; then
          if mount | grep -q '#{volume['mount']}'; then
            umount '#{volume['mount']}'
          fi

          mv /etc/fstab /etc/fstab.bak
          cat /etc/fstab.bak | grep -v '#{volume['mount']}\\b' > /etc/fstab
          echo '#{device_name} #{volume['mount']} #{volume['filesystem']} #{volume['mount_opts'] ? volume['mount_opts'] : 'noatime'} 0 0 # rubber LVM volume' >> /etc/fstab
        fi

        # Check if the logical volume exists or not.
        if ! lvdisplay #{device_name} >> /dev/null 2>&1; then
          # Create the logical volume.
          lvcreate -L #{volume['size']}G -i #{volume['stripes'] || 1} -n#{volume['name']} #{volume_group_name}

          # Format the logical volume.
          yes | mkfs -t #{volume['filesystem']} #{volume['filesystem_opts']} #{device_name}

          # Create the mount point.
          mkdir -p '#{volume['mount']}'

          # Mount the volume.
          mount '#{volume['mount']}'
        else
          # Try to extend the volume size.
          if lvextend -L #{volume['size']}G -i #{volume['stripes'] || 1} #{device_name} >> /dev/null 2&>1; then

            # If we actually resized the volume, then we need to resize the filesystem.
            #{resize_command}
          fi
        fi
      ENDSCRIPT
    end

    task :_setup_lvm_group, :hosts => ic.external_ip do
      rubber.sudo_script 'setup_lvm_group', <<-ENDSCRIPT
        # Check and see if the physical volume is already set up for LVM. If not, initialize it to be so.
        for device in #{physical_volumes.join(' ')}
        do
          if ! pvdisplay $device >> /dev/null 2>&1; then

            if grep $device /etc/mtab; then
              umount $device
            fi

            if grep -q "$device" /etc/fstab; then
              mv /etc/fstab /etc/fstab.bak
              cat /etc/fstab.bak | grep -v "$device\\b" > /etc/fstab
            fi

            pvcreate $device

            # See if the volume group already exists. If so, add the new physical volume to it.
            if vgdisplay #{volume_group_name} >> /dev/null 2>&1; then
              vgextend #{volume_group_name} $device
            fi
          fi
        done

        # If the volume group does not exist yet, construct it with all the physical volumes.
        if ! vgdisplay #{volume_group_name} >> /dev/null 2>&1; then
          vgcreate #{volume_group_name} #{physical_volumes.join(' ')} -s #{extent_size}
        fi

        # Set up each of the logical volumes.
        #{volumes.collect { |volume| create_logical_volume_in_bash(volume, volume_group_name) }.join("\n\n") }
      ENDSCRIPT
    end
    _setup_lvm_group
  end

  def detach_volume(volume_id)
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

    logger.info "Detaching volume #{volume_id} from rubber instances file"
    rubber_instances.each do |ic|
      ic.volumes.delete(volume_id) if ic.volumes
    end
    rubber_instances.save

  end
  
  def destroy_volume(volume_id)
    cloud.before_destroy_volume(volume_id)

    logger.info "Deleting volume #{volume_id}"
    cloud.destroy_volume(volume_id) rescue logger.info("Volume did not exist in cloud")

    cloud.after_destroy_volume(volume_id)

    logger.info "Removing volume #{volume_id} from rubber instances file"
    artifacts = rubber_instances.artifacts
    artifacts['volumes'].delete_if {|k,v| v == volume_id}
    rubber_instances.save
  end

end
