module VagrantPlugins
  module Rubber
    class Plugin < Vagrant.plugin("2")
      name 'rubber'
      description 'Provides support for provisioning your virtual machines with Rubber.'

      command(:rubber) do
        require File.expand_path('../command', __FILE__)
        Command
      end

      config(:rubber, :provisioner) do
        require File.expand_path('../config', __FILE__)
        Config
      end

      provisioner(:rubber) do
        require File.expand_path('../provisioner', __FILE__)
        Provisioner
      end
    end
  end
end
