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