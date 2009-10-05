require 'nettica/client'
module Rubber
  module Dns

    class Nettica < Base

      def initialize(env)
        super(env, "nettica")
        @client = ::Nettica::Client.new(provider_env.user, provider_env.password)
      end

      def check_status(response)
        code = case
          when response.respond_to?(:status)
            response.status
          when response.respond_to?(:result)
            response.result.status
          else
            500
        end
        if code < 200 || code > 299
          msg = "Failed to access nettica api (http_status=#{code})"
          msg += ", check dns_providers.nettica.user/password in rubber.yml" if code == 401
          raise msg
        end
        return response
      end

      def find_host_records(opts = {})
        opts = setup_opts(opts, [:host, :domain])

        result = []
        hn = opts[:host]
        ht = opts[:type]
        hd = opts[:data]

        domain_info = check_status @client.list_domain(opts[:domain])
        raise "Domain needs to exist in nettica before records can be updated" unless domain_info.record

        domain_info.record.each do |h|
          keep = true
          if hn && h.hostName != hn && hn != '*'
            keep = false
          end
          if ht && h.recordType != ht && ht != '*'
            keep = false
          end
          if hd && h.data != hd
            keep = false
          end
          result << record_to_opts(h) if keep
        end

        return result
      end

      def create_host_record(opts = {})
        opts = setup_opts(opts, [:host, :data, :domain, :type, :ttl])
        record = opts_to_record(opts)
        check_status @client.add_record(record)
      end

      def destroy_host_record(opts = {})
        find_host_records(opts).each do |h|
          record = opts_to_record(h)
          check_status @client.delete_record(record)
        end
      end

      def update_host_record(old_opts = {}, new_opts = {})
        old_opts = setup_opts(old_opts, [:host, :domain])
        find_host_records(old_opts).each do |h|
          old_record = opts_to_record(h)
          new_record = opts_to_record(h.merge(new_opts))
          check_status @client.update_record(old_record, new_record)
        end
      end

      private

      def opts_to_record(opts)
        record = @client.create_domain_record(opts[:domain],
                                              opts[:host],
                                              opts[:type],
                                              opts[:data],
                                              opts[:ttl],
                                              opts[:priority] || 0)
        return record
      end

      def record_to_opts(record)
        opts = {}
        opts[:host] = record.hostName
        opts[:domain] = record.domainName
        opts[:type] = record.recordType
        opts[:data] = record.data
        opts[:ttl] = record.tTL
        opts[:priority] = record.priority
        return opts
      end
    end

  end
end
