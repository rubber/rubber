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

        create || refresh
        bootstrap && deploy_migrations
      end

      def cleanup
        destroy
      end

      private

      #comma separated ssh keys for rubber.
      def rubber_ssh_keys
        Array(ssh_info[:private_key_path]).join(',')
      end

      def create
        if config.use_vagrant_ruby
          script = "RUN_FROM_VAGRANT=true RUBBER_ENV=#{config.rubber_env} ALIAS=#{machine.name} ROLES='#{config.roles}' EXTERNAL_IP=#{private_ip} INTERNAL_IP=#{private_ip} RUBBER_SSH_KEY=#{rubber_ssh_keys} #{internal_cap_command} rubber:create -S initial_ssh_user=#{ssh_info[:username]}"
        else
          script = <<-ENDSCRIPT
            unset GEM_HOME;
            unset GEM_PATH;
            PATH=#{ENV['PATH'].split(':')[1..-1].join(':')} RUN_FROM_VAGRANT=true RUBBER_ENV=#{config.rubber_env} ALIAS=#{machine.name} ROLES='#{config.roles}' EXTERNAL_IP=#{private_ip} INTERNAL_IP=#{private_ip} RUBBER_SSH_KEY=#{rubber_ssh_keys} bash -c '#{rvm_prefix} bundle exec cap rubber:create -S initial_ssh_user=#{ssh_info[:username]}'
          ENDSCRIPT
        end

        system(script)
      end

      def destroy
        if config.use_vagrant_ruby
          script = "RUN_FROM_VAGRANT=true FORCE=true RUBBER_ENV=#{config.rubber_env} ALIAS=#{machine.name} #{internal_cap_command} rubber:destroy"
        else
          script = <<-ENDSCRIPT
            unset GEM_HOME;
            unset GEM_PATH;
            PATH=#{ENV['PATH'].split(':')[1..-1].join(':')} RUN_FROM_VAGRANT=true FORCE=true RUBBER_ENV=#{config.rubber_env} ALIAS=#{machine.name} bash -c '#{rvm_prefix} bundle exec cap rubber:destroy'
          ENDSCRIPT
        end

        system(script)
      end

      def refresh
        if config.use_vagrant_ruby
          script = "RUN_FROM_VAGRANT=true RUBBER_ENV=#{config.rubber_env} RUBBER_SSH_KEY=#{rubber_ssh_keys} ALIAS=#{machine.name} EXTERNAL_IP=#{private_ip} INTERNAL_IP=#{private_ip} #{internal_cap_command} rubber:refresh -S initial_ssh_user=#{ssh_info[:username]}"
        else
          script = <<-ENDSCRIPT
            unset GEM_HOME;
            unset GEM_PATH;
            PATH=#{ENV['PATH'].split(':')[1..-1].join(':')} RUN_FROM_VAGRANT=true RUBBER_ENV=#{config.rubber_env} RUBBER_SSH_KEY=#{rubber_ssh_keys} ALIAS=#{machine.name} EXTERNAL_IP=#{private_ip} INTERNAL_IP=#{private_ip} bash -c '#{rvm_prefix} bundle exec cap rubber:refresh -S initial_ssh_user=#{ssh_info[:username]}'
          ENDSCRIPT
        end

        system(script)
      end

      def bootstrap
        if config.use_vagrant_ruby
          script = "RUN_FROM_VAGRANT=true RUBBER_ENV=#{config.rubber_env} RUBBER_SSH_KEY=#{rubber_ssh_keys} FILTER=#{machine.name} #{internal_cap_command} rubber:bootstrap"
        else
          script = <<-ENDSCRIPT
            unset GEM_HOME;
            unset GEM_PATH;
            PATH=#{ENV['PATH'].split(':')[1..-1].join(':')} RUN_FROM_VAGRANT=true RUBBER_ENV=#{config.rubber_env} RUBBER_SSH_KEY=#{rubber_ssh_keys} FILTER=#{machine.name} bash -c '#{rvm_prefix} bundle exec cap rubber:bootstrap'
          ENDSCRIPT
        end

        system(script)
      end

      def deploy_migrations
        if config.use_vagrant_ruby
          script = "RUN_FROM_VAGRANT=true RUBBER_ENV=#{config.rubber_env} RUBBER_SSH_KEY=#{rubber_ssh_keys} FILTER=#{machine.name} #{internal_cap_command} deploy:migrations"
        else
          script = <<-ENDSCRIPT
            unset GEM_HOME;
            unset GEM_PATH;
            PATH=#{ENV['PATH'].split(':')[1..-1].join(':')} RUN_FROM_VAGRANT=true RUBBER_ENV=#{config.rubber_env} RUBBER_SSH_KEY=#{rubber_ssh_keys} FILTER=#{machine.name} bash -c '#{rvm_prefix} bundle exec cap deploy:migrations'
          ENDSCRIPT
        end

        system(script)
      end

      def internal_cap_command
        "ruby -e \"require 'capistrano/cli'; Capistrano::CLI.execute\""
      end

      def rvm_prefix
        config.rvm_ruby_version ? "rvm #{config.rvm_ruby_version} do" : ''
      end
    end
  end
end
