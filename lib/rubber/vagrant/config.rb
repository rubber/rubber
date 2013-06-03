module VagrantPlugins
  module Rubber
    class Config < Vagrant.plugin("2", :config)
      attr_accessor :roles

      def initialize
        ::Rubber::initialize(Dir.pwd, 'vagrant')

        @roles = UNSET_VALUE
      end

      def finalize!
        @roles = ::Rubber.config['staging_roles'] if @roles == UNSET_VALUE
      end

      def validate(machine)
        if @roles.nil?
          return { 'rubber' => ['roles must be set to a list of roles to use for this machine']}
        end

        {}
      end
    end
  end
end
