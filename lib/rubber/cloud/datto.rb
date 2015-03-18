require 'rubber/cloud/generic'
require 'net/http'
module Rubber
  module Cloud
    class Datto < Base
      def initialize(env, capistrano)
        super(env, capistrano)
      end

      def endpoint
        env.endpoint
      end

      def active_state
        'running'
      end

      def stopped_state
        'stopped'
      end

      def create_instance(instance_alias, image_name, image_type, security_groups, availability_zone, datacenter)
        response = HttpAdapter.post(uriBuilder)
        if response.code != 200
          raise errFromResponse(response)
        end

        response["id"]
      end

      def describe_instances(instance_id=nil)
        instances = []
        if instance_id.nil?
          response = HttpAdapter.get(uriBuilder)
          if response.code != 200
            raise errFromResponse(response)
          end

          response["results"].each do |item|
            instance = {}
            instance[:id] = item["id"]
            instance[:external_ip] = item["ip"]
            instance[:internal_ip] = item["ip"]
            instance[:provider] = 'datto'
            instances << instance
          end
        else
          response = HttpAdapter.get(uriBuilder(instance_id))
          if response.code != 200
            raise errFromResponse(response)
          end

          instance = {}
          instance[:id] = response["id"]
          instance[:external_ip] = response["ip"]
          instance[:internal_ip] = response["ip"]
          instance[:state] = response["workerRunning"] ? active_state : stopped_state
          instance[:provider] = 'datto'
          instance[:platform] = Rubber::Platforms::LINUX
          instances << instance
        end
        instances
      end

      def destroy_instance(instance_id)
        response = HttpAdapter.delete(uriBuilder(instance_id))
        if response.code != 200
          raise errFromResponse(response)
        end
        response
      end

      private

      # @param [HTTPartyResponse] response
      # @return [StandardError]
      def errFromResponse(response)
        StandardError.new(response["result"] || "Unexpected Response Code #{response.code}")
      end

      def uriBuilder(path = nil)
        base = "http://#{self.endpoint}/index.php/worker"
        path.nil? ? base : File.join(base, path)
      end

      class HttpAdapter
        include HTTParty
        format(:json)
      end
    end
  end
end
