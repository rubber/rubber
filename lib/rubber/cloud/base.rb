module Rubber
  module Cloud

    class Base

      attr_reader :env, :capistrano

      def initialize(env, capistrano)
        @env = env
        @capistrano = capistrano
      end

      def before_create_instance(instance_alias, role_names)
        # No-op by default.
      end

      def after_create_instance(instance)
        # No-op by default.
      end

      def before_refresh_instance(instance)
        # No-op by default.
      end

      def after_refresh_instance(instance)
        # No-op by default.
      end

    end

  end
end