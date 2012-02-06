require 'rubygems'
require 'fog'
require 'rubber/dns/fog'

module Rubber
  module Dns

    class Zerigo < Fog

      def initialize(env)
        super(env.merge({"credentials" => { "provider" => 'zerigo', "zerigo_email" => env.email, "zerigo_token" => env.token }}))
      end
    
    end
    
  end
end
