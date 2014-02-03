require 'rubber/cloud/fog'

module Rubber
  module Cloud
    class Vsphere < Fog
      def initialize(env, capistrano)
        compute_credentials = {
          :provider => 'vsphere',
          :vsphere_username => env.vcenter_username,
          :vsphere_password => env.vcenter_password,
          :vsphere_server => env.vcenter_host,
          :vsphere_expected_pubkey_hash => env.expected_pubkey_hash
        }

        if env.cloud_providers && env.cloud_providers.aws
          storage_credentials = {
              :provider => 'AWS',
              :aws_access_key_id => env.cloud_providers.aws.access_key,
              :aws_secret_access_key => env.cloud_providers.aws.secret_access_key,
              :path_style => true
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

        if host_env.public_nic && env.public_network_name.nil?
          raise "You must configure the 'public_network_name' in the provider configuration"
        end

        if host_env.private_nic && env.private_network_name.nil?
          raise "You must configure the 'private_network_name' in the provider configuration"
        end

        nics = []

        if host_env.public_nic
          nic = nic_to_vsphere_config(host_env.public_nic, env.public_nic || {})
          validate_nic_vsphere_config(nic, :public)
          nics << nic
        end

        if host_env.private_nic
          nic = nic_to_vsphere_config(host_env.private_nic, env.private_nic || {})
          validate_nic_vsphere_config(nic, :private)
          nics << nic
        end

        vm_clone_options = {
          'datacenter' => datacenter,
          'template_path' => image_name,
          'name' => instance_alias,
          'power_on' => false
        }

        if host_env.memory
          vm_clone_options['memoryMB'] = host_env.memory
        end

        if host_env.cpus
          vm_clone_options['numCPUs'] = host_env.cpus
        end

        vm = compute_provider.vm_clone(vm_clone_options)

        server = compute_provider.servers.get(vm['new_vm']['id'])

        # Destroy all existing NICs.  We need the public and private IPs to line up with the NICs attached to the
        # correct virtual switches.  Rather than take the cross-product and try to work that out, it's easier to
        # just start fresh and guarantee everything works as intended.
        server.interfaces.each(&:destroy)

        server.interfaces.create(:network => env.public_network_name) if host_env.public_nic
        server.interfaces.create(:network => env.private_network_name) if host_env.private_nic

        vm_ref = compute_provider.send(:get_vm_ref, server.id)
        vm_ref.CustomizeVM_Task(:spec => customization_spec(instance_alias, nics))

        server.start

        vm['new_vm']['id']
      end

      def destroy_instance(instance_id)
        compute_provider.servers.get(instance_id).destroy(:force => true)
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
          rubber_cfg = Rubber::Configuration.get_configuration(Rubber.env)
          host_env = rubber_cfg.environment.bind(nil, item.name)

          instance = {}
          instance[:id] = item.id
          instance[:state] = item.tools_state

          # We can't trust the describe operation when the instance is newly created because the VM customization
          # step likely hasn't completed yet.  This means we'll get back the IP address for the VM template, rather
          # than the one we just configured.
          if host_env.public_nic
            instance[:external_ip] = host_env.public_nic.ip_address

            if host_env.private_nic.nil?
              instance[:internal_ip] = host_env.public_nic.ip_address
            end
          end

          if host_env.private_nic
            instance[:internal_ip] = host_env.private_nic.ip_address

            if host_env.public_nic.nil?
              instance[:external_ip] = host_env.private_nic.ip_address
            end
          end

          instance[:region_id] = item.datacenter
          instance[:provider] = 'vsphere'
          instance[:platform] = Rubber::Platforms::LINUX
          instances << instance
        end

        return instances
      end

      def active_state
        'toolsOk'
      end

      def create_volume(instance, volume_spec)
        server = compute_provider.servers.get(instance.instance_id)
        datastore = volume_spec['datastore']
        thin_disk = volume_spec.has_key?('thin') ? volume_spec['thin'] : true

        # This craziness here is so we can map the device name to an appropriate SCSI channel index, which is zero-based.
        # E.g., /dev/sdc would correspond to a unit_number of 2.  We do this by chopping off the SCSI device letter and
        # then doing some ASCII value math to convert to the appropriate decimal value.
        unit_number = volume_spec['device'][-1].ord - 97

        config = { :size_gb => volume_spec['size'], :unit_number => unit_number }

        if datastore
          config[:datastore] = datastore
        end

        unless thin_disk
          eager_zero = volume_spec.has_key?('eager_zero') ? volume_spec['eager_zero'] : false

          config[:thin] = false
          config[:eager_zero] = eager_zero
        end

        volume = server.volumes.create(config)

        volume.id
      end

      def destroy_volume(volume_id)
        # TODO (nirvdrum 10/28/13): Fog currently lacks the ability to fetch a volume by ID, so we need to fetch all volumes for all servers to find the volume we want.  This is terribly inefficient and fog should be updated.
        volume = compute_provider.servers.collect { |s| s.volumes.all }.flatten.find { |v| v.id == volume_id }

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
          response = [compute_provider.servers.collect { |s| s.volumes.all }.flatten.find { |v| v.id == volume_id }]
        else
          response = compute_provider.servers.collect { |s| s.volumes.all }.flatten
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

      def should_disable_password_based_ssh_login?
        true
      end

      private

      def validate_nic_vsphere_config(nic_config, type)
        %w[ip subnetMask dnsServerList].each do |attr|
          if nic_config[attr].nil?
            raise "Missing '#{attr}' for #{type} NIC configuaration"
          end
        end

        nic_config
      end

      def nic_to_vsphere_config(nic, default_nic)
        hash = {
          'ip' => nic['ip_address'],
          'subnetMask' => nic['subnet_mask'] || default_nic['subnet_mask'],
          'dnsServerList' => nic['dns_servers'] || default_nic['dns_servers']
        }

        # We want to allow overriding the gateway on a per-host basis by setting the value to nil.  As such, we
        # can't fall back to the default config just because the value is nil.
        if nic.has_key?('gateway')

          # Null values are represented as "null" in YAML, but Rubyists tend to use "nil", which will get translated
          # to the literal String "nil". Which guarding against this is arguably bad, letting "nil" go through as a valid
          # gateway value is even worse.
          if nic['gateway'] && nic['gateway'] != 'nil'
            hash['gateway'] = [nic['gateway']]
          end

        elsif default_nic['gateway']
          hash['gateway'] = [default_nic['gateway']]
        end

        hash
      end

      def customization_spec(instance_alias, ip_settings)
        nics = []

        ip_settings.each do |nic|
          custom_ip_settings = RbVmomi::VIM::CustomizationIPSettings.new(nic)
          custom_ip_settings.ip = RbVmomi::VIM::CustomizationFixedIp("ipAddress" => nic['ip'])
          custom_ip_settings.dnsDomain = env.domain

          nics << custom_ip_settings
        end

        custom_global_ip_settings = RbVmomi::VIM::CustomizationGlobalIPSettings.new
        custom_global_ip_settings.dnsServerList = nics.first.dnsServerList
        custom_global_ip_settings.dnsSuffixList = [env.domain]

        custom_adapter_mapping = nics.collect { |nic| RbVmomi::VIM::CustomizationAdapterMapping.new("adapter" => nic) }

        custom_prep = RbVmomi::VIM::CustomizationLinuxPrep.new(
            :domain => env.domain,
            :hostName => RbVmomi::VIM::CustomizationFixedName.new(:name => instance_alias))

        puts "Adapters: #{custom_adapter_mapping}"

        RbVmomi::VIM::CustomizationSpec.new(:identity => custom_prep,
                                            :globalIPSettings => custom_global_ip_settings,
                                            :nicSettingMap => custom_adapter_mapping)
      end
    end
  end
end