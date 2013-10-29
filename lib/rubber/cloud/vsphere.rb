require 'rubber/cloud/fog'

module Rubber
  module Cloud
    class Vsphere < Fog
      def initialize(env, capistrano)
        compute_credentials = {
          :provider => 'vsphere',
          :vsphere_username => env.vsphere.username,
          :vsphere_password => env.vsphere.password,
          :vsphere_server => env.vsphere.host,
          :vsphere_expected_pubkey_hash => env.vsphere.expected_pubkey_hash
        }

        if env.cloud_providers && env.cloud_providers.aws
          storage_credentials = {
              :provider => 'AWS',
              :aws_access_key_id => env.cloud_providers.aws.access_key,
              :aws_secret_access_key => env.cloud_providers.aws.secret_access_key
          }

          storage_credentials[:region] = env.cloud_providers.aws.region

          env['storage_credentials'] = storage_credentials
        end

        env['compute_credentials'] = compute_credentials
        super(env, capistrano)
      end

      def create_instance(instance_alias, image_name, image_type, security_groups, availability_zone, datacenter)
        if env.domain.nil?
          raise "'domain' value must be configured"
        end

        rubber_cfg = Rubber::Configuration.get_configuration(Rubber.env)
        host_env = rubber_cfg.environment.bind(nil, instance_alias)

        if host_env.public_nic.nil? && host_env.private_nic.nil?
          raise "You must configure a private or a public NIC for this host in your rubber YAML"
        end

        nic = host_env.public_nic || host_env.private_nic
        vm = compute_provider.vm_clone('datacenter' => datacenter,
                                       'template_path' => image_name,
                                       'name' => instance_alias,
                                       'customization_spec' => {
                                           'domain' => env.domain,
                                           'ipsettings' => {
                                               'ip' => nic.ip_address,
                                               'subnetMask' => nic.subnet_mask,
                                               'gateway' => [nic.gateway],
                                               'dnsServerList' => [nic.dns_servers]
                                           }
                                       })

        vm['new_vm']['id']
      end

      def describe_instances(instance_id=nil)
        instances = []
        opts = {}

        if instance_id
          response = [compute_provider.servers.get(instance_id)]
        else
          response = compute_provider.servers.all(opts)
        end

        response.each do |item|
          instance = {}
          instance[:id] = item.id
          instance[:state] = item.tools_state
          instance[:external_ip] = item.public_ip_address
          instance[:internal_ip] = item.public_ip_address
          instance[:region_id] = item.datacenter
          instance[:provider] = 'vsphere'
          instance[:platform] = 'linux'
          instances << instance
        end

        return instances
      end

      def active_state
        'toolsOk'
      end

      def create_volume(instance, volume_spec)
        server = @compute_provider.servers.get(instance.instance_id)
        datastore = volume_spec['datastore']

        # This craziness here is so we can map the device name to an appropriate SCSI channel index, which is zero-based.
        # E.g., /dev/sdc would correspond to a unit_number of 2.  We do this by chopping off the SCSI device letter and
        # then doing some ASCII value math to convert to the appropriate decimal value.
        unit_number = volume_spec['device'][-1].ord - 97

        if datastore
          volume = server.volumes.create(:size_gb => volume_spec['size'], :datastore => datastore, :unit_number => unit_number)
        else
          volume = server.volumes.create(:size_gb => volume_spec['size'], :unit_number => unit_number)
        end

        volume.id
      end

      def destroy_volume(volume_id)
        # TODO (nirvdrum 10/28/13): Fog currently lacks the ability to fetch a volume by ID, so we need to fetch all volumes for all servers to find the volume we want.  This is terribly inefficient and fog should be updated.
        volume = @compute_provider.servers.collect { |s| s.volumes.all }.flatten.find { |v| v.id == volume_id }

        if volume.unit_number == 0
          raise "Cannot destroy volume because it is the VM root device.  Destroy the VM if you really want to free this volume."
        end

        volume.destroy
      end

      def describe_volumes(volume_id=nil)
        volumes = []
        opts = {}
        opts[:'volume-id'] = volume_id if volume_id

        if volume_id
          response = [@compute_provider.servers.collect { |s| s.volumes.all }.flatten.find { |v| v.id == volume_id }]
        else
          response = @compute_provider.servers.collect { |s| s.volumes.all }.flatten
        end

        response.each do |item|
          volume = {}
          volume[:id] = item.id
          volume[:status] = item.unit_number == 0 ? 'root' : 'extra'

          if item.server_id
            volume[:attachment_instance_id] = item.server_id
            volume[:attachment_status] = Thread.current[:detach_volume] == item.id ? 'detached' : 'attached'
          end

          volumes << volume
        end

        volumes
      end

      def should_destroy_volume_when_instance_destroyed?
        true
      end

      private

      def validate_nic(nic, type)
        %w[ip_address subnet_mask gateway dns_servers].each do |attr|
          if nic[attr].nil?
            raise "Missing '#{attr}' for #{type} NIC configuaration"
          end
        end
      end
    end
  end
end