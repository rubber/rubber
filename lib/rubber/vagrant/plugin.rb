module VagrantPlugins
  module Rubber
    class Plugin < Vagrant.plugin("2")
      name 'rubber'
      description 'Provides support for provisioning your virtual machines with Rubber.'

      command(:rubber) do
        require_relative 'command'
        Command
      end

      config(:rubber, :provisioner) do
        require_relative 'config'
        Config
      end

      provisioner(:rubber) do
        require_relative 'provisioner'
        Provisioner
      end
    end
  end
end
