require 'nettica/client'
module Rubber
  module Dns

    class Nettica < Base

      def initialize(env)
        super(env)
        @client = Nettica::Client.new(env.dns_user, env.dns_password)
        @ttl = (env.dns_ttl || 300).to_i
        @record_type = env.dns_record_type || "A"
      end

      def nameserver
        "dns1.nettica.com"
      end

      def host_exists?(host)
        domain_info = @client.list_domain(env.domain)
        raise "Domain needs to exist in nettica before records can be updated" unless domain_info.record
        return domain_info.record.any? { |r| r.hostName == host }
      end

      def create_host_record(host, ip)
        new = @client.create_domain_record(env.domain, host, @record_type, ip, @ttl, 0)
        @client.add_record(new)
      end

      def destroy_host_record(host)
        old_record = @client.list_domain(env.domain).record.find {|r| r.hostName == host }
        old = @client.create_domain_record(env.domain, host, old_record.recordType, old_record.data, old_record.tTL, old_record.priority)
        @client.delete_record(old)
      end

      def update_host_record(host, ip)
        old_record = @client.list_domain(env.domain).record.find {|r| r.hostName == host }
        update_record(host, ip, old_record)
      end

      # update the top level domain record which has an empty hostName
      def update_domain_record(ip)
        old_record = @client.list_domain(env.domain).record.find {|r| r.hostName == '' and r.recordType == 'A' and r.data =~ /\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\z/}
        update_record('', ip, old_record)
      end

      def update_record(host, ip, old_record)
        old = @client.create_domain_record(env.domain, host, old_record.recordType, old_record.data, old_record.tTL, old_record.priority)
        new = @client.create_domain_record(env.domain, host, @record_type, ip, @ttl, 0)
        @client.update_record(old, new)
      end

    end

  end
end
