module VagrantPlugins
  module Rubber
    class Provisioner < Vagrant.plugin("2", :provisioner)
      attr_reader :ssh_info, :private_ip

      def configure(root_config)
        root_config.vm.networks.each do |type, info|
          if type == :private_network
            @private_ip = info[:ip]
          end
        end

        if @private_ip.nil?
          $stderr.puts "Rubber requires a private network address to be configured in your Vagrantfile."
          exit(-1)
        end
      end

      def provision
        @ssh_info = machine.ssh_info

        create
        bootstrap && deploy_migrations
      end

      private

      def create
        script = <<-ENDSCRIPT
          unset GEM_HOME;
          unset GEM_PATH;
          PATH=#{ENV['PATH'].split(':')[1..-1].join(':')} RUN_FROM_VAGRANT=true RUBBER_ENV=vagrant ALIAS=#{machine.name} ROLES='#{config.roles}' EXTERNAL_IP=#{private_ip} INTERNAL_IP=#{private_ip} RUBBER_SSH_KEY=#{ssh_info[:private_key_path]} bash -c 'bundle exec cap rubber:create -S initial_ssh_user=#{ssh_info[:username]}'
        ENDSCRIPT

        $stderr.puts script

        system(script)
      end

      def bootstrap
        script = <<-ENDSCRIPT
          unset GEM_HOME;
          unset GEM_PATH;
          PATH=#{ENV['PATH'].split(':')[1..-1].join(':')} RUN_FROM_VAGRANT=true RUBBER_ENV=vagrant RUBBER_SSH_KEY=#{ssh_info[:private_key_path]} FILTER=#{machine.name} bash -c 'bundle exec cap rubber:bootstrap'
        ENDSCRIPT

        system(script)
      end

      def deploy_migrations
        script = <<-ENDSCRIPT
          unset GEM_HOME;
          unset GEM_PATH;
          PATH=#{ENV['PATH'].split(':')[1..-1].join(':')} RUN_FROM_VAGRANT=true RUBBER_ENV=vagrant RUBBER_SSH_KEY=#{ssh_info[:private_key_path]} FILTER=#{machine.name} bash -c 'bundle exec cap deploy:migrations'
        ENDSCRIPT

        system(script)
      end
    end
  end
end
