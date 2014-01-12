module VagrantPlugins
  module Rubber
    class Command < Vagrant.plugin("2", :command)

      def execute
        require 'rubber'
        ::Rubber::initialize(Dir.pwd, 'vagrant')

        require 'rubber/cli'
        success = ::Rubber::CLI.run(Dir.pwd, @argv)

        success ? 0 : 1
      end

    end
  end
end
