require "vagrant"

module VagrantPlugins
  module Rubber
    class Plugin < Vagrant.plugin("2")
      name "rubber"
      description <<-DESC
      Provides support for provisioning your virtual machines with
      shell scripts.
      DESC

      provisioner(:rubber) do
        require File.expand_path("../provisioner", __FILE__)
        Provisioner
      end
    end
  end
end
