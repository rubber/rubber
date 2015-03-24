require 'rubber/cloud/generic'
require 'httparty'

module Rubber
  module Cloud
    class Datto < Base
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
        response = HttpAdapter.post(uri_builder)
        if response.code != 200
          raise err_from_response(response)
        end

        response["id"]
      end

      def describe_instances(instance_id=nil)
        instances = []
        if instance_id.nil?
          response = HttpAdapter.get(uri_builder)
          if response.code != 200
            raise err_from_response(response)
          end

          response["results"].each do |item|
            instances << instance_from_response(item)
          end
        else
          response = HttpAdapter.get(uri_builder(instance_id))
          if response.code != 200
            raise err_from_response(response)
          end

          instances << instance_from_response(response)
        end
        instances
      end

      def destroy_instance(instance_id)
        response = HttpAdapter.delete(uri_builder(instance_id))
        if response.code != 200
          raise err_from_response(response)
        end
        response
      end

      private

      # @param [Hash] response - response hash representing an instance
      # @param [Hash] converted hash conforming to the rubber instance api.
      def instance_from_response(response)
        instance = {}
        instance[:id] = response["id"]
        instance[:external_ip] = response["ip"]
        instance[:internal_ip] = response["ip"]
        instance[:state] = response["workerRunning"] ? active_state : stopped_state
        instance[:provider] = "datto"
        instance[:platform] = Rubber::Platforms::LINUX
        instance
      end

      # @param [HTTPartyResponse] response
      # @return [StandardError]
      def err_from_response(response)
        StandardError.new(response["result"] || "Unexpected Response Code #{response.code}")
      end

      # Creates the uri from the specified path and the configured endpoint.
      # @param [String|Nil] path
      # @return String - uri
      def uri_builder(path = nil)
        base = "http://#{endpoint}/index.php/worker"
        path.nil? ? base : File.join(base, path)
      end

      class HttpAdapter
        include ::HTTParty
        format(:json)
      end
    end
  end
end
