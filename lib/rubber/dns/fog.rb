require 'rubygems'
require 'fog'

module Rubber
  module Dns

    class Fog < Base

      attr_accessor :client
      
      def initialize(env)
        super(env)
        creds = Rubber::Util.symbolize_keys(env.credentials)
        @client = ::Fog::DNS.new(creds)
      end

      def host_to_opts(host)
        opts = {}
        opts[:id] = host.id
        opts[:host] = host.name || ''
        opts[:type] = host.type
        opts[:data] = host.value if host.value
        opts[:ttl] = host.ttl if host.ttl
        opts[:priority] = host.priority if host.priority
        return opts
      end

      def opts_to_host(opts, host={})
        host[:name] = opts[:host]
        host[:type] =  opts[:type]
        host[:value] = opts[:data] if opts[:data]
        host[:ttl] = opts[:ttl] if opts[:ttl]
        host[:priority] = opts[:priority] if opts[:priority]
        return host
      end

      def find_or_create_zone(domain)
        zone = @client.zones.all.find {|z| z.domain =~ /#{domain}\.?/}
        if ! zone
          zone = @client.zones.create(:domain => domain)
        end
        return zone
      end
      
      def find_hosts(opts = {})
        opts = setup_opts(opts, [:host, :domain])
        result = []
        zone = find_or_create_zone(opts[:domain])

        host_type = opts[:type]
        host_data = opts[:data]

        fqdn = nil
        if opts.has_key?(:host) && opts[:host] != '*'
          hostname = opts[:host]
          hostname = nil if hostname && hostname.strip.empty?

          fqdn = ""
          fqdn << "#{hostname}." if hostname
          fqdn << "#{opts[:domain]}"
        end

        hosts = fqdn ? (zone.records.find(fqdn) rescue []) : zone.records.all
        hosts.each do |h|
          keep = true

          if host_type && h.type != host_type && host_type != '*'
            keep = false
          end

          if host_data && h.value != host_data
            keep = false
          end

          result << h if keep
        end

        result
      end

      def find_host_records(opts = {})
        hosts = find_hosts(opts)
        result = hosts.collect {|h| host_to_opts(h).merge(:domain => opts[:domain]) }
        return result
      end

      def create_host_record(opts = {})
        opts = setup_opts(opts, [:host, :data, :domain, :type, :ttl])
        zone = find_or_create_zone(opts[:domain])
        zone.records.create(opts_to_host(opts))
      end

      def destroy_host_record(opts = {})
        opts = setup_opts(opts, [:host, :domain])

        find_hosts(opts).each do |h|
          h.destroy || raise("Failed to destroy #{h.hostname}")
        end
      end

      def update_host_record(old_opts={}, new_opts={})
        old_opts = setup_opts(old_opts, [:host, :domain])
        new_opts = setup_opts(new_opts, [:host, :domain, :type, :data])

        find_hosts(old_opts).each do |h|
          opts_to_host(new_opts).each do |k, v|
            h.send("#{k}=", v)
          end

          h.save || raise("Failed to update host #{h.hostname}, #{h.errors.full_messages.join(', ')}")
        end
      end

    end

  end
end
