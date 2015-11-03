require 'fog'
require 'fog/digitalocean/compute_v2'
require 'fog/digitalocean/requests/compute_v2/create_ssh_key'
require 'fog/digitalocean/requests/compute_v2/list_ssh_keys'
require 'fog/digitalocean/requests/compute_v2/delete_ssh_key'

module ::Fog
  module Compute
    class DigitalOceanV2
      # Fixes an ssh key creation issue currently in fog 1.35.0
      # This change currently in fog master:
      #   https://github.com/fog/fog/pull/3743
      # However, unless it gets backported into 1.x, we'll need this patch until
      # we update fog to 2.x
      class Real
        def create_ssh_key(name, public_key)
          create_options = {
            :name       => name,
            :public_key => public_key,
          }

          encoded_body = Fog::JSON.encode(create_options)

          request(
            :expects => [201],
            :headers => {
              'Content-Type' => "application/json; charset=UTF-8",
            },
            :method  => 'POST',
            :path    => '/v2/account/keys',
            :body    => encoded_body,
          )
        end
      end

      class Mock
        def create_ssh_key(name, public_key)
          response        = Excon::Response.new
          response.status = 201

          data[:ssh_keys] << {
            "id" => Fog::Mock.random_numbers(6).to_i,
            "fingerprint" => (["00"] * 16).join(':'),
            "public_key" => public_key,
            "name" => name
          }

          response.body ={
            'ssh_key' => data[:ssh_keys].last
          }

          response
        end

        def list_ssh_keys
          response = Excon::Response.new
          response.status = 200
          response.body = {
            "ssh_keys" => data[:ssh_keys],
            "links" => {},
            "meta" => {
              "total" => data[:ssh_keys].count
            }
          }
          response
        end

        def delete_ssh_key(id)
          self.data[:ssh_keys].select! do |key|
            key["id"] != id
          end

          response        = Excon::Response.new
          response.status = 204
          response
        end
      end
    end
  end
end
