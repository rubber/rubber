module VagrantPlugins
  module Rubber
    class Config < Vagrant.plugin("2", :config)
      attr_accessor :roles, :rubber_env

      def initialize
        @roles = UNSET_VALUE
        @rubber_env = UNSET_VALUE
      end

      def finalize!
        @rubber_env = 'vagrant' if @rubber_env == UNSET_VALUE

        ::Rubber::initialize(Dir.pwd, @rubber_env)

        @roles = ::Rubber.config['staging_roles'] if @roles == UNSET_VALUE
      end

      def validate(machine)
        if @rubber_env.nil?
          return { 'rubber' => ['rubber_env must be set to the Rubber environment to use for this cluster'] }
        end

        if @roles.nil?
          return { 'rubber' => ['roles must be set to a list of roles to use for this machine'] }
        end

        {}
      end
    end
  end
end
