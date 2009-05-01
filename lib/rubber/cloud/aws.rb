require 'rubygems'
require 'EC2'
require 'aws/s3'

module Rubber
  module Cloud

    class Aws < Base

      def initialize(env)
        super(env)
        @ec2 = EC2::Base.new(:access_key_id => env.aws_access_key, :secret_access_key => env.aws_secret_access_key)
        AWS::S3::Base.establish_connection!(:access_key_id => env.aws_access_key, :secret_access_key => env.aws_secret_access_key)
      end


      def create_instance(ami, ami_type, security_groups, availability_zone)
        response = ec2.run_instances(:image_id => ami, :key_name => @env.ec2_key_name, :instance_type => ami_type, :group_id => security_groups, :availability_zone => availability_zone)
        instance_id = response.instancesSet.item[0].instanceId
        return instance_id
      end

      def describe_instances(instance_id=nil)
        instances = []

        response = @ec2.describe_instances(instance_id => instance_id)
        response.reservationSet.item.each do |ritem|
          ritem.instancesSet.item.each do |item|
            instance = {}
            instance[:id] = item.instanceId
            instance[:external_host] = item.dnsName
            instance[:external_ip] = IPSocket.getaddress(instance[:external_host]) rescue nil
            instance[:internal_host] = item.privateDnsName
            instance[:state] = item.instanceState.name
            instance[:zone] = item.placement.availabilityZone
            instances << instance
          end
        end if response.reservationSet

        return instances
      end

      def destroy_instance(instance_id)
        response = @ec2.terminate_instances(:instance_id => instance_id)
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
        response = @ec2.describe_addresses()
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
          if attach = item.attachmentSet.item[0]
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

      def create_image
        raise NotImplementedError.new
      end

      def upload_image
        raise NotImplementedError.new
      end

      def register_image(image_location)
        response = @ec2.register_image(:image_location => image_location)
        return response.imageId
      end

      def deregister_image(image_id)
        @ec2.deregister_image(:image_id => image_id)
      end

      def describe_images(image_id=nil)
        images = []
        response = @ec2.describe_images(:owner_id => 'self', :image_id => image_id)
        response.imagesSet.item.each do |item|
          image = {}
          image[:id] = item.imageId
          image[:location] = item.imageLocation
          images << image
        end if response.imagesSet
        return images
      end

      def destroy_image(image_id)
        image = describe_images(image_id).first
        image_location = image[:location]
        bucket = image_location.split('/').first
        image_name = image_location.split('/').last.gsub(/\.manifest\.xml$/, '')

        deregister_image(image_id)

        s3_bucket = AWS::S3::Bucket.find(bucket)
        s3_bucket.objects(:prefix => image_name).clone.each do |obj|
          obj.delete
        end
        if s3_bucket.empty?
          s3_bucket.delete
        end
      end

    end

  end
end
