module VagrantPlugins
  module Rubber
    class Config < Vagrant.plugin("2", :config)
      attr_accessor :roles, :rubber_env, :use_vagrant_ruby, :rvm_ruby_version

      def initialize
        @roles = UNSET_VALUE
        @rubber_env = UNSET_VALUE
        @use_vagrant_ruby = UNSET_VALUE
        @rvm_ruby_version = UNSET_VALUE
      end

      def finalize!
        @rubber_env = 'vagrant' if @rubber_env == UNSET_VALUE
        @use_vagrant_ruby = false if @use_vagrant_ruby == UNSET_VALUE
        @rvm_ruby_version = nil if @rvm_ruby_version == UNSET_VALUE

        ::Rubber::initialize(Dir.pwd, @rubber_env)

        @roles = ::Rubber.config['staging_roles'] if @roles == UNSET_VALUE
      end

      def validate(machine)
        if @rubber_env.nil?
          return { 'rubber' => ['rubber_env must be set to the Rubber environment to use for this cluster'] }
        end

        unless [true, false].include?(@use_vagrant_ruby)
          return { 'rubber' => ['use_vagrant_ruby must be set to a Boolean value'] }
        end

        if @roles.nil?
          return { 'rubber' => ['roles must be set to a list of roles to use for this machine'] }
        end

        {}
      end
    end
  end
end
