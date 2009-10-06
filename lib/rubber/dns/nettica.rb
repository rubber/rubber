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

        domain_info = find_or_create_zone(opts[:domain])

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
        find_or_create_zone(opts[:domain])
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
        new_opts = setup_opts(new_opts.merge(:no_defaults =>true), [])
        find_host_records(old_opts).each do |h|
          old_record = opts_to_record(h)
          new_record = opts_to_record(h.merge(new_opts))
          check_status @client.update_record(old_record, new_record)
        end
      end

      private

      def find_or_create_zone(domain)
        domain_info = @client.list_domain(domain)
        if domain_info.record
          check_status domain_info
        else
          check_status @client.create_zone(domain)
          domain_info = check_status @client.list_domain(domain)
          raise "Could not create zone in nettica: #{domain}" unless domain_info.record
        end
        return domain_info
      end

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
        opts[:host] = record.hostName || ''
        opts[:domain] = record.domainName
        opts[:type] = record.recordType
        opts[:data] = record.data if record.data
        opts[:ttl] = record.tTL if record.tTL
        opts[:priority] = record.priority if record.priority
        return opts
      end
    end

  end
end
