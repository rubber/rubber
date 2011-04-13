require 'rubygems'
require 'AWS'
require 'aws/s3'

module Rubber
  module Cloud

    class Aws < Base

      def initialize(env, capistrano)
        super(env, capistrano)
        @aws_env = env.cloud_providers.aws
        @ec2 = AWS::EC2::Base.new(:access_key_id => @aws_env.access_key, :secret_access_key => @aws_env.secret_access_key, :server => @aws_env.server_endpoint)
        @ec2elb = AWS::ELB::Base.new(:access_key_id => @aws_env.access_key, :secret_access_key => @aws_env.secret_access_key, :server => @aws_env.server_endpoint)
        AWS::S3::Base.establish_connection!(:access_key_id => @aws_env.access_key, :secret_access_key => @aws_env.secret_access_key, :server => @aws_env.server_endpoint)
      end

      def create_instance(ami, ami_type, security_groups, availability_zone)
        response = @ec2.run_instances(:image_id => ami, :key_name => @aws_env.key_name, :instance_type => ami_type, :security_group => security_groups, :availability_zone => availability_zone)
        instance_id = response.instancesSet.item[0].instanceId
        return instance_id
      end

      def create_spot_instance_request(spot_price, ami, ami_type, security_groups, availability_zone)
        response = @ec2.request_spot_instances(:spot_price => spot_price, :image_id => ami, :key_name => @aws_env.key_name, :instance_type => ami_type, :security_group => security_groups, :availability_zone => availability_zone)
        request_id = response.spotInstanceRequestSet.item[0].spotInstanceRequestId
        return request_id
      end

      def describe_instances(instance_id=nil)
        instances = []
        opts = {}
        opts[:instance_id] = instance_id if instance_id

        response = @ec2.describe_instances(opts)
        response.reservationSet.item.each do |ritem|
          ritem.instancesSet.item.each do |item|
            instance = {}
            instance[:id] = item.instanceId
            instance[:external_host] = item.dnsName
            instance[:external_ip] = item.ipAddress
            instance[:internal_host] = item.privateDnsName
            instance[:internal_ip] = item.privateIpAddress
            instance[:state] = item.instanceState.name
            instance[:zone] = item.placement.availabilityZone
            instance[:platform] = item.platform || 'linux'
            instance[:root_device_type] = item.rootDeviceType
            instances << instance
          end
        end if response.reservationSet

        return instances
      end

      def destroy_instance(instance_id)
        response = @ec2.terminate_instances(:instance_id => instance_id)
      end

      def reboot_instance(instance_id)
        response = @ec2.reboot_instances(:instance_id => instance_id)
      end

      def stop_instance(instance_id)
        # Don't force the stop process. I.e., allow the instance to flush its file system operations.
        response = @ec2.stop_instances(:instance_id => instance_id, :force => false)
      end

      def start_instance(instance_id)
        response = @ec2.start_instances(:instance_id => instance_id)
      end

      def describe_availability_zones
        zones = []
        response = @ec2.describe_availability_zones()
        response.availabilityZoneInfo.item.each do |item|
          zone = {}
          zone[:name] = item.zoneName
          zone[:state] =item.zoneState
          zones << zone
        end if response.availabilityZoneInfo
        return zones
      end

      def create_security_group(group_name, group_description)
        @ec2.create_security_group(:group_name => group_name, :group_description => group_description)
      end

      def describe_security_groups(group_name=nil)
        groups = []

        opts = {}
        opts[:group_name] = group_name if group_name
        response = @ec2.describe_security_groups(opts)

        response.securityGroupInfo.item.each do |item|
          group = {}
          group[:name] = item.groupName
          group[:description] = item.groupDescription

          item.ipPermissions.item.each do |ip_item|
            group[:permissions] ||= []
            rule = {}

            rule[:protocol] = ip_item.ipProtocol
            rule[:from_port] = ip_item.fromPort
            rule[:to_port] = ip_item.toPort

            ip_item.groups.item.each do |rule_group|
              rule[:source_groups] ||= []
              source_group = {}
              source_group[:account] = rule_group.userId
              source_group[:name] = rule_group.groupName
              rule[:source_groups] << source_group
            end if ip_item.groups

            ip_item.ipRanges.item.each do |ip_range|
              rule[:source_ips] ||= []
              rule[:source_ips] << ip_range.cidrIp
            end if ip_item.ipRanges

            group[:permissions] << rule
          end if item.ipPermissions

          groups << group
          
        end if response.securityGroupInfo

        return groups
      end

      def add_security_group_rule(group_name, protocol, from_port, to_port, source)
        opts = {:group_name => group_name}
        if source.instance_of? Hash
          opts = opts.merge(:source_security_group_name => source[:name], :source_security_group_owner_id => source[:account])
        else
          opts = opts.merge(:ip_protocol => protocol, :from_port => from_port, :to_port => to_port, :cidr_ip => source)
        end
        @ec2.authorize_security_group_ingress(opts)
      end

      def remove_security_group_rule(group_name, protocol, from_port, to_port, source)
        opts = {:group_name => group_name}
        if source.instance_of? Hash
          opts = opts.merge(:source_security_group_name => source[:name], :source_security_group_owner_id => source[:account])
        else
          opts = opts.merge(:ip_protocol => protocol, :from_port => from_port, :to_port => to_port, :cidr_ip => source)
        end
        @ec2.revoke_security_group_ingress(opts)
      end

      def destroy_security_group(group_name)
        @ec2.delete_security_group(:group_name => group_name)
      end

      def create_static_ip
        response = @ec2.allocate_address()
        return response.publicIp
      end

      def attach_static_ip(ip, instance_id)
        response = @ec2.associate_address(:instance_id => instance_id, :public_ip => ip)
        return response.return == "true"
      end

      def detach_static_ip(ip)
        response = @ec2.disassociate_address(:public_ip => ip)
        return response.return == "true"
      end

      def describe_static_ips(ip=nil)
        ips = []
        opts = {}
        opts[:public_ip] = ip if ip
        response = @ec2.describe_addresses(opts)
        response.addressesSet.item.each do |item|
          ip = {}
          ip[:instance_id] = item.instanceId
          ip[:ip] = item.publicIp
          ips << ip
        end if response.addressesSet
        return ips
      end

      def destroy_static_ip(ip)
        response = @ec2.release_address(:public_ip => ip)
        return response.return == "true"
      end

      def create_volume(size, zone)
        response = @ec2.create_volume(:size => size.to_s, :availability_zone => zone)
        return response.volumeId
      end

      def attach_volume(volume_id, instance_id, device)
        response = @ec2.attach_volume(:volume_id => volume_id, :instance_id => instance_id, :device => device)
        return response.status
      end

      def detach_volume(volume_id)
        @ec2.detach_volume(:volume_id => volume_id, :force => 'true')
      end

      def describe_volumes(volume_id=nil)
        volumes = []
        opts = {}
        opts[:volume_id] = volume_id if volume_id
        response = @ec2.describe_volumes(opts)
        response.volumeSet.item.each do |item|
          volume = {}
          volume[:id] = item.volumeId
          volume[:status] = item.status
          if item.attachmentSet
            attach = item.attachmentSet.item[0]
            volume[:attachment_instance_id] = attach.instanceId
            volume[:attachment_status] = attach.status
          end
          volumes << volume
        end if response.volumeSet
        return volumes
      end

      def destroy_volume(volume_id)
        @ec2.delete_volume(:volume_id => volume_id)
      end

      def create_image(image_name)
        ec2_key = @aws_env.key_file
        ec2_pk = @aws_env.pk_file
        ec2_cert = @aws_env.cert_file
        ec2_key_dest = "/mnt/#{File.basename(ec2_key)}"
        ec2_pk_dest = "/mnt/#{File.basename(ec2_pk)}"
        ec2_cert_dest = "/mnt/#{File.basename(ec2_cert)}"

        capistrano.put(File.read(ec2_key), ec2_key_dest)
        capistrano.put(File.read(ec2_pk), ec2_pk_dest)
        capistrano.put(File.read(ec2_cert), ec2_cert_dest)

        arch = capistrano.capture("uname -m").strip
        arch = case arch when /i\d86/ then "i386" else arch end

        capistrano.sudo_script "create_bundle", <<-CMD
          rvm use system
          export RUBYLIB=/usr/lib/site_ruby/
          unset RUBYOPT
          nohup ec2-bundle-vol --batch -d /mnt -k #{ec2_pk_dest} -c #{ec2_cert_dest} -u #{@aws_env.account} -p #{image_name} -r #{arch} &> /tmp/ec2-bundle-vol.log &
          sleep 1

          echo "Creating image from instance volume..."
          while true; do
            if ! ps ax | grep -q "[e]c2-bundle-vol"; then exit; fi
            echo -n .
            sleep 5
          done
        CMD

        capistrano.sudo_script "register_bundle", <<-CMD
          rvm use system
          export RUBYLIB=/usr/lib/site_ruby/
          unset RUBYOPT
          echo "Uploading image to S3..."
          ec2-upload-bundle --batch -b #{@aws_env.image_bucket} -m /mnt/#{image_name}.manifest.xml -a #{@aws_env.access_key} -s #{@aws_env.secret_access_key}
        CMD

        image_location = "#{@aws_env.image_bucket}/#{image_name}.manifest.xml"
        response = @ec2.register_image(:image_location => image_location)
        return response.imageId
      end

      def describe_images(image_id=nil)
        images = []
        opts = {:owner_id => 'self'}
        opts[:image_id] = image_id if image_id
        response = @ec2.describe_images(opts)
        response.imagesSet.item.each do |item|
          image = {}
          image[:id] = item.imageId
          image[:location] = item.imageLocation
          image[:root_device_type] = item.rootDeviceType
          images << image
        end if response.imagesSet
        return images
      end

      def destroy_image(image_id)
        image = describe_images(image_id).first
        raise "Could not find image: #{image_id}, aborting destroy_image" if image.nil?
        image_location = image[:location]
        bucket = image_location.split('/').first
        image_name = image_location.split('/').last.gsub(/\.manifest\.xml$/, '')

        @ec2.deregister_image(:image_id => image_id)

        s3_bucket = AWS::S3::Bucket.find(bucket)
        s3_bucket.objects(:prefix => image_name).clone.each do |obj|
          obj.delete
        end
        if s3_bucket.empty?
          s3_bucket.delete
        end
      end

      def destroy_spot_instance_request(request_id)
        @ec2.cancel_spot_instance_requests :spot_instance_request_id => request_id
      end

      def describe_load_balancers(name=nil)
        lbs = []
        opts = {}
        opts[:load_balancer_names] = name if name
        response = @ec2elb.describe_load_balancers(opts)
        response.describeLoadBalancersResult.member.each do |member|
          lb = {}
          lb[:name] = member.loadBalancerName
          lb[:dns_name] = member.dNSName

          member.availabilityZones.member.each do |zone|
            lb[:zones] ||= []
            lb[:zones] << zone
          end

          member.listeners.member.each do |member|
            listener = {}
            listener[:protocol] = member.protocol
            listener[:port] = member.loadBalancerPort
            listener[:instance_port] = member.instancePort
            lb[:listeners] ||= []
            lb[:listeners] << listener
          end

          lbs << lb
        end if response.describeLoadBalancersResult
        return lbs
      end

      def describe_spot_instance_requests(request_id=nil)
        requests = []
        opts = {}
        opts[:spot_instance_request_id] = request_id if request_id
        response = @ec2.describe_spot_instance_requests(opts)
        response.spotInstanceRequestSet.item.each do |item|
          request = {}
          request[:id] = item.spotInstanceRequestId
          request[:spot_price] = item.spotPrice
          request[:state] = item.state
          request[:created_at] = item.createTime
          request[:type] = item.launchSpecification.instanceType
          request[:image_id] = item.launchSpecification.imageId
          request[:instance_id] = item.instanceId
          requests << request
        end if response.spotInstanceRequestSet
        return requests
      end

      # resource_id is any Amazon resource ID (e.g., instance ID or volume ID)
      # tags is a hash of tag_name => tag_value pairs
      def create_tags(resource_id, tags)
        # Tags needs to be an array of hashes, not one big hash, so break it down.
        @ec2.create_tags(:resource_id => resource_id, :tag => tags.collect { |k, v| { k.to_s => v.to_s } })
      end

    end

  end
end
