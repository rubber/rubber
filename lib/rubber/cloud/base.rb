module Rubber
  module Cloud

    class Base

      attr_reader :env, :capistrano

      def initialize(env, capistrano)
        @env = env
        @capistrano = capistrano
      end

    end

  end
end