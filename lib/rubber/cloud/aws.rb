require 'rubber/cloud/fog'
require 'rubber/cloud/aws_table_store'

module Rubber
  module Cloud
  
    class Aws < Fog
      
      def initialize(env, capistrano)
        
        credentials = {
            :aws_access_key_id => env.access_key,
            :aws_secret_access_key => env.secret_access_key
        }
        
        @table_store = ::Fog::AWS::SimpleDB.new(credentials)
        
        credentials[:region] = env.region
        @elb = ::Fog::AWS::ELB.new(credentials)
        
        credentials[:provider] = 'AWS'
        env['credentials'] = credentials
        super(env, capistrano)
      end
      
      def table_store(table_key)
        return Rubber::Cloud::AwsTableStore.new(@table_store, table_key)  
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
          sleep 1

          echo "Creating image from instance volume..."
          while true; do
            if ! ps ax | grep -q "[e]c2-bundle-vol"; then exit; fi
            echo -n .
            sleep 5
          done
        CMD

        capistrano.sudo_script "register_bundle", <<-CMD
          export RUBYLIB=/usr/lib/site_ruby/
          unset RUBYOPT
          echo "Uploading image to S3..."
          ec2-upload-bundle --batch -b #{env.image_bucket} -m /mnt/#{image_name}.manifest.xml -a #{env.access_key} -s #{env.secret_access_key}
        CMD

        image_location = "#{env.image_bucket}/#{image_name}.manifest.xml"
        response = @compute_provider.register_image(image_name,
                                                    "rubber bundled image",
                                                    image_location)
        return response.body["imageId"]
      end

      def destroy_image(image_id)
        image = @compute_provider.images.get(image_id)
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

    end

  end
end
