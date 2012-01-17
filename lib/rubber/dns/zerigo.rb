require 'rubygems'
require 'fog'

module Rubber
  module Dns

    class Zerigo < Fog

      def initialize(env)
        super(env)

        @client = Fog::DNS.new({
            :provider     => 'zerigo',
            :zerigo_email => provider_env.email,
            :zerigo_token => provider_env.token
          })
      end

  end
end
