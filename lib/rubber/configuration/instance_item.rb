require 'rubber/configuration/server'

module Rubber
  module Configuration
    class InstanceItem < Server
      def initialize(*args)
        super *args

        Rubber.logger.warn "[DEPRECATED] Rubber::Configuration::InstanceItem has been replaced with Rubber::Configuration::Server.  If you don't have any custom code that references this class directly, this problem should fix itself and you shouldn't see these messages again.  If you are referencing this class directly, please use Rubber::Configuration::Server instead."
      end
    end
  end
end
