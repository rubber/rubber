require 'rubber/cloud/fog'
require 'rubber/cloud/aws'

module Rubber
  module Cloud

    class Aws::Base < Fog

      def initialize(env, capistrano)

        compute_credentials = {
          :aws_access_key_id => env.access_key,
          :aws_secret_access_key => env.secret_access_key
        }

        storage_credentials = {
          :provider => 'AWS',
          :aws_access_key_id => env.access_key,
          :aws_secret_access_key => env.secret_access_key,
          :path_style => true
        }

        @table_store = ::Fog::AWS::SimpleDB.new(compute_credentials)

        compute_credentials[:region] = env.region
        @elb = ::Fog::AWS::ELB.new(compute_credentials)

        compute_credentials[:provider] = 'AWS' # We need to set the provider after the SimpleDB init because it fails if the provider value is specified.

        storage_credentials[:region] = env.region

        env['compute_credentials'] = compute_credentials
        env['storage_credentials'] = storage_credentials
        super(env, capistrano)
      end

      def table_store(table_key)
        return Rubber::Cloud::Aws::TableStore.new(@table_store, table_key)
      end

      def describe_instances(instance_id=nil)
        instances = []
        opts = {}
        opts["instance-id"] = instance_id if instance_id

        response = compute_provider.servers.all(opts)
        response.each do |item|
          instance = {}
          instance[:id] = item.id
          instance[:type] = item.flavor_id
          instance[:external_host] = item.dns_name
          instance[:external_ip] = item.public_ip_address
          instance[:internal_host] = item.private_dns_name
          instance[:internal_ip] = item.private_ip_address
          instance[:state] = item.state
          instance[:zone] = item.availability_zone
          instance[:provider] = 'aws'
          instance[:platform] = item.platform || Rubber::Platforms::LINUX
          instance[:root_device_type] = item.root_device_type
          instances << instance
        end

        return instances
      end

      def active_state
        'running'
      end

      def stopped_state
        'stopped'
      end

      def before_create_instance(instance)
        setup_security_groups(instance.name, instance.role_names)
      end

      def after_create_instance(instance)
        # Sometimes tag creation will fail, indicating that the instance doesn't exist yet even though it does.  It seems to
        # be a propagation delay on Amazon's end, so the best we can do is wait and try again.
        Rubber::Util.retry_on_failure(StandardError, :retry_sleep => 1, :retry_count => 120) do
          Rubber::Tag::update_instance_tags(instance.name)
        end
      end

      def after_refresh_instance(instance)
        # Sometimes tag creation will fail, indicating that the instance doesn't exist yet even though it does.  It seems to
        # be a propagation delay on Amazon's end, so the best we can do is wait and try again.
        Rubber::Util.retry_on_failure(StandardError, :retry_sleep => 1, :retry_count => 120) do
          Rubber::Tag::update_instance_tags(instance.name)
        end
      end

      def before_stop_instance(instance)
        capistrano.fatal "Cannot stop spot instances!" if ! instance.spot_instance_request_id.nil?
        capistrano.fatal "Cannot stop instances with instance-store root device!" if (instance.root_device_type != 'ebs')
      end

      def before_start_instance(instance)
        capistrano.fatal "Cannot start spot instances!" if ! instance.spot_instance_request_id.nil?
        capistrano.fatal "Cannot start instances with instance-store root device!" if (instance.root_device_type != 'ebs')
      end

      def after_start_instance(instance)
        # Re-starting an instance will almost certainly give it a new set of IPs and DNS entries, so refresh the values.
        capistrano.rubber.refresh_instance(instance.name)

        # Static IPs, DNS, etc. need to be set up for the started instance.
        capistrano.rubber.post_refresh
      end

      def create_image(image_name)

        # validate all needed config set
        ["key_file", "pk_file", "cert_file", "account", "secret_access_key", "image_bucket"].each do |k|
          raise "Set #{k} in rubber.yml" unless "#{env[k]}".strip.size > 0
        end
        raise "create_image can only be called from a capistrano scope" unless capistrano

        ec2_key = env.key_file
        ec2_pk = env.pk_file
        ec2_cert = env.cert_file

        ec2_key_dest = "/mnt/#{File.basename(ec2_key)}"
        ec2_pk_dest = "/mnt/#{File.basename(ec2_pk)}"
        ec2_cert_dest = "/mnt/#{File.basename(ec2_cert)}"

        storage(env.image_bucket).ensure_bucket

        capistrano.put(File.read(ec2_key), ec2_key_dest)
        capistrano.put(File.read(ec2_pk), ec2_pk_dest)
        capistrano.put(File.read(ec2_cert), ec2_cert_dest)

        arch = capistrano.capture("uname -m").strip
        arch = case arch when /i\d86/ then "i386" else arch end

        capistrano.sudo_script "create_bundle", <<-CMD
          export RUBYLIB=/usr/lib/site_ruby/
          unset RUBYOPT
          nohup ec2-bundle-vol --batch -d /mnt -k #{ec2_pk_dest} -c #{ec2_cert_dest} -u #{env.account} -p #{image_name} -r #{arch} &> /tmp/ec2-bundle-vol.log &
          bg_pid=$!
          sleep 1

          echo "Creating image from instance volume..."
          while kill -0 $bg_pid &> /dev/null; do
            echo -n .
            sleep 5
          done

          # this returns exit code even if pid has already died, and thus triggers fail fast shell error
          wait $bg_pid
        CMD

        capistrano.sudo_script "register_bundle", <<-CMD
          export RUBYLIB=/usr/lib/site_ruby/
          unset RUBYOPT
          echo "Uploading image to S3..."
          ec2-upload-bundle --batch -b #{env.image_bucket} -m /mnt/#{image_name}.manifest.xml -a #{env.access_key} -s #{env.secret_access_key}
        CMD

        image_location = "#{env.image_bucket}/#{image_name}.manifest.xml"
        response = compute_provider.register_image(image_name,
                                                    "rubber bundled image",
                                                    image_location)
        return response.body["imageId"]
      end

      def destroy_image(image_id)
        image = compute_provider.images.get(image_id)
        raise "Could not find image: #{image_id}, aborting destroy_image" if image.nil?

        location_parts = image.location.split('/')
        bucket = location_parts.first
        image_name = location_parts.last.gsub(/\.manifest\.xml$/, '')

        image.deregister

        storage(bucket).walk_tree(image_name) do |f|
          f.destroy
        end
      end

      def describe_load_balancers(name=nil)
        lbs = []
        response = name.nil? ? @elb.load_balancers.all() : [@elb.load_balancers.get(name)].compact
        response.each do |item|
          lb = {}
          lb[:name] = item.id
          lb[:dns_name] = item.dns_name
          lb[:zones] = item.availability_zones

          item.listeners.each do |litem|
            listener = {}
            listener[:protocol] = litem.protocol
            listener[:port] = litem.lb_portPort
            listener[:instance_port] = litem.instance_port
            lb[:listeners] ||= []
            lb[:listeners] << listener
          end

          lbs << lb
        end
        return lbs
      end

      def describe_availability_zones
        zones = []
        response = compute_provider.describe_availability_zones()
        items = response.body["availabilityZoneInfo"]
        items.each do |item|
          zone = {}
          zone[:name] = item["zoneName"]
          zone[:state] =item["zoneState"]
          zones << zone
        end
        return zones
      end

      def create_spot_instance_request(spot_price, ami, ami_type, security_groups, availability_zone, fog_options={})
        response = compute_provider.spot_requests.create({:price => spot_price,
                                                          :image_id => ami,
                                                          :flavor_id => ami_type,
                                                          :groups => security_groups,
                                                          :availability_zone => availability_zone,
                                                          :key_name => env.key_name}.merge(Rubber::Util.symbolize_keys(fog_options)))
        request_id = response.id
        return request_id
      end

      def describe_spot_instance_requests(request_id=nil)
        requests = []
        opts = {}
        opts["spot-instance-request-id"] = request_id if request_id
        response = compute_provider.spot_requests.all(opts)
        response.each do |item|
          request = {}
          request[:id] = item.id
          request[:spot_price] = item.price
          request[:state] = item.state
          request[:created_at] = item.created_at
          request[:type] = item.flavor_id
          request[:image_id] = item.image_id
          request[:instance_id] = item.instance_id
          requests << request
        end
        return requests
      end

      def setup_security_groups(host=nil, roles=[])
        raise NotImplementedError("Implement #setup_security_groups")
      end

      def describe_security_groups(group_name=nil)
        raise NotImplementedError("Implement #describe_security_groups")
      end

      def create_volume(instance, volume_spec)
        fog_options = Rubber::Util.symbolize_keys(volume_spec['fog_options'] || {})
        volume_data = {
          :size => volume_spec['size'],
          :availability_zone => volume_spec['zone'],
          :snapshot_id => volume_spec['snapshot_id']
        }.merge(fog_options)
        volume = compute_provider.volumes.create(volume_data)
        volume.id
      end

      def after_create_volume(instance, volume_id, volume_spec)
        # After we create an EBS volume, we need to attach it to the instance.
        volume = compute_provider.volumes.get(volume_id)
        server = compute_provider.servers.get(instance.instance_id)
        volume.device = volume_spec['device']
        volume.server = server
      end

      def before_destroy_volume(volume_id)
        # Before we can destroy an EBS volume, we must detach it from any running instances.
        volume = compute_provider.volumes.get(volume_id)
        volume.force_detach
      end

      def destroy_volume(volume_id)
        compute_provider.volumes.get(volume_id).destroy
      end

      def describe_volumes(volume_id=nil)
        volumes = []
        opts = {}
        opts[:'volume-id'] = volume_id if volume_id
        response = compute_provider.volumes.all(opts)

        response.each do |item|
          volume = {}
          volume[:id] = item.id
          volume[:status] = item.state

          if item.server_id
            volume[:attachment_instance_id] = item.server_id
            volume[:attachment_status] = item.attached_at ? "attached" : "waiting"
          end

          volumes << volume
        end

        volumes
      end

      # resource_id is any Amazon resource ID (e.g., instance ID or volume ID)
      # tags is a hash of tag_name => tag_value pairs
      def create_tags(resource_id, tags)
        # Tags need to be created individually in fog
        tags.each do |k, v|
          compute_provider.tags.create(:resource_id => resource_id,
                                        :key => k.to_s, :value => v.to_s)
        end
      end
    end
  end
end
