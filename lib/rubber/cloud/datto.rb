require 'rubber/cloud/generic'
require 'net/http'
require 'pry'

module Rubber
  module Cloud
    class Datto < Base
      delegate :endpoint, :to => :env

      def initialize(env, capistrano)
        super(env, capistrano)
        binding.pry
      end

      def active_state
        'running'
      end

      def stopped_state
        'stopped'
      end

      def create_instance(instance_alias, image_name, image_type, security_groups, availability_zone, datacenter)
        binding.pry
        # if env.domain.nil?
        #   raise "'domain' value must be configured"
        # end

        # rubber_cfg = Rubber::Configuration.get_configuration(Rubber.env)
        # host_env = rubber_cfg.environment.bind(nil, instance_alias)

        # if host_env.public_nic.nil? && host_env.private_nic.nil?
        #   raise "You must configure a private or a public NIC for this host in your rubber YAML"
        # end

        # if host_env.public_nic && env.public_network_name.nil?
        #   raise "You must configure the 'public_network_name' in the provider configuration"
        # end

        # if host_env.private_nic && env.private_network_name.nil?
        #   raise "You must configure the 'private_network_name' in the provider configuration"
        # end

        # nics = []

        # if host_env.public_nic
        #   nic = nic_to_vsphere_config(host_env.public_nic, env.public_nic || {})
        #   validate_nic_vsphere_config(nic, :public)
        #   nics << nic
        # end

        # if host_env.private_nic
        #   nic = nic_to_vsphere_config(host_env.private_nic, env.private_nic || {})
        #   validate_nic_vsphere_config(nic, :private)
        #   nics << nic
        # end

        # vm_clone_options = {
        #   'datacenter' => datacenter,
        #   'template_path' => image_name,
        #   'name' => instance_alias,
        #   'power_on' => false
        # }

        # if host_env.memory
        #   vm_clone_options['memoryMB'] = host_env.memory
        # end

        # if host_env.cpus
        #   vm_clone_options['numCPUs'] = host_env.cpus
        # end

        # vm = compute_provider.vm_clone(vm_clone_options)

        # server = compute_provider.servers.get(vm['new_vm']['id'])

        # # Destroy all existing NICs.  We need the public and private IPs to line up with the NICs attached to the
        # # correct virtual switches.  Rather than take the cross-product and try to work that out, it's easier to
        # # just start fresh and guarantee everything works as intended.
        # server.interfaces.each(&:destroy)

        # server.interfaces.create(:network => env.public_network_name) if host_env.public_nic
        # server.interfaces.create(:network => env.private_network_name) if host_env.private_nic

        # vm_ref = compute_provider.send(:get_vm_ref, server.id)
        # vm_ref.CustomizeVM_Task(:spec => customization_spec(instance_alias, nics))

        # server.start

        # vm['new_vm']['id']
      end

      def describe_instances(instance_id=nil)
        binding.pry
        # response = httpAdapter.get('http://10.30.95.138/index.php/worker')
        # response["results"]
      #   output = `vagrant status #{instance_id}`

      #   output =~ /#{instance_id}\s+(\w+)/m
      #   state = $1

      #   if Generic.instances
      #     Generic.instances.each do |instance|
      #       if instance[:id] == instance_id
      #         instance[:state] = state
      #         instance[:provider] = 'vagrant'
      #       end
      #     end

      #     Generic.instances
      #   else
      #     instance = {}
      #     instance[:id] = instance_id
      #     instance[:state] = state
      #     instance[:external_ip] = capistrano.rubber.get_env('EXTERNAL_IP', "External IP address for host '#{instance_id}'", true)
      #     instance[:internal_ip] = capistrano.rubber.get_env('INTERNAL_IP', "Internal IP address for host '#{instance_id}'", true, instance[:external_ip])
      #     instance[:provider] = 'vagrant'

      #     [instance]
      #   end

        # TODO
      end

      def destroy_instance(instance_id)
        # response = httpAdapter.delete("http://10.30.95.138/index.php/worker/#{instance}")
        binding.pry
      end

      # def stop_instance(instance, force=false)
      #   system("vagrant suspend #{instance.instance_id}")
      # end

      # def start_instance(instance)
      #   system("vagrant resume #{instance.instance_id}")
      # end

      private

      class HttpAdapter
        include HTTParty
        format(:json)
      end
    end
  end
end
