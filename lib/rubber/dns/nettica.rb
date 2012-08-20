begin
  require 'nettica/client'
rescue LoadError
  Rubber::Util.fatal "Missing the nettica gem.  Install or add it to your Gemfile."
end

module Rubber
  module Dns

    class Nettica < Base

      def initialize(env)
        super(env)
        @client = ::Nettica::Client.new(env.user, env.password)
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

      def find_hosts(opts = {})
        opts = setup_opts(opts, [:host, :domain])

        result = []
        hn = opts[:host]
        ht = opts[:type]

        domain_info = find_or_create_zone(opts[:domain])

        domain_info.record.each do |h|
          keep = true
          if hn && h.hostName != hn && hn != '*'
            keep = false
          end
          if ht && h.recordType != ht && ht != '*'
            keep = false
          end
          result << h if keep
        end

        return result
      end

      def find_host_records(opts = {})
        hosts = find_hosts(opts)
        group = {}
        hosts.each do |h|
          key = "#{h.hostName}.#{h.domainName} #{h.recordType}"
          group[key] ||= []
          group[key] << h
        end
        result = group.values.collect {|h| hosts_to_opts(h).merge(:domain => opts[:domain])}
        return result
      end
      
      def create_host_record(opts = {})
        opts = setup_opts(opts, [:host, :data, :domain, :type, :ttl])
        find_or_create_zone(opts[:domain])
        opts_to_hosts(opts).each do |host|
          check_status @client.add_record(host)
        end
      end

      def destroy_host_record(opts = {})
        opts = setup_opts(opts, [:host, :domain])

        find_hosts(opts).each do |h|
          check_status @client.delete_record(h)
        end
      end

      def update_host_record(old_opts = {}, new_opts = {})
        old_opts = setup_opts(old_opts, [:host, :domain, :type])
        new_opts = setup_opts(new_opts, [:host, :domain, :type, :data])

        # Tricky to update existing hosts since nettica needs a separate host
        # entry for multiple records of same type (MX, etc), so take the easy
        # way out and destroy/create instead of update
        destroy_host_record(old_opts)
        create_host_record(new_opts)
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
      
      # multiple hosts with same name/type convert to a single rubber-dns.yml opts format
      def hosts_to_opts(hosts)
        opts = {}
        
        hosts.each do |record|
          opts[:host] ||= record.hostName || ''
          opts[:domain] ||= record.domainName
          opts[:type] ||= record.recordType
          opts[:ttl] ||= record.tTL if record.tTL

          opts[:data] ||= []
          if opts[:type] =~ /MX/i
            opts[:data] << {:priority => record.priority, :value => record.data}
          else
            opts[:data] << record.data
          end
        end
        
        return opts
      end

      # a single rubber-dns.yml opts format converts to multiple hosts with same name/type 
      def opts_to_hosts(opts)
        hosts = []
        
        opts[:data].each do |o|
          
          data, priority = nil, 0
          if o.kind_of?(Hash) && o[:priority]
            priority = o[:priority]
            data = o[:value]
          else
            data = o
          end
          
          host = @client.create_domain_record(opts[:domain],
                                              opts[:host],
                                              opts[:type],
                                              data,
                                              opts[:ttl],
                                              priority)
          hosts << host
        end
        
        return hosts
      end
      
    end

  end
end
