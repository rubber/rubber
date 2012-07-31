require 'rubygems'
require 'fog'

module Rubber
  module Dns

    class Zerigo < Base

      attr_accessor :client
          
      def initialize(env)
        super(env)
        creds = { :provider => 'zerigo', :zerigo_email => env.email, :zerigo_token => env.token }
        @client = ::Fog::DNS.new(creds)
      end
      
      # multiple hosts with same name/type convert to a single rubber-dns.yml opts format
      def hosts_to_opts(hosts)
        opts = {}
        
        hosts.each do |host|
          opts[:host] ||= host.name || ''
          opts[:domain] ||= host.zone.domain
          opts[:type] ||= host.type
          opts[:ttl] ||= host.ttl.to_i if host.ttl
          
          opts[:data] ||= []
          if host.type =~ /MX/i
            opts[:data] << {:priority => host.priority, :value => host.value}
          else
            opts[:data] << host.value
          end
        end
        
        return opts
      end

      # a single rubber-dns.yml opts format converts to multiple hosts with same name/type 
      def opts_to_hosts(opts)
        hosts = []
        
        opts[:data].each do |o|
          host = {}
          host[:name] = opts[:host]
          host[:type] =  opts[:type]
          host[:ttl] = opts[:ttl] if opts[:ttl]
          if o.kind_of?(Hash) && o[:priority]
            host[:priority] = o[:priority]
            host[:value] = o[:value]
          else
            host[:value] = o
          end
          hosts << host
        end
        
        return hosts
      end

      def find_or_create_zone(domain)
        zone = @client.zones.all.find {|z| z.domain =~ /^#{domain}\.?/}
        if ! zone
          zone = @client.zones.create(:domain => domain)
        end
        return zone
      end
      
      def find_hosts(opts = {})
        opts = setup_opts(opts, [:host, :domain])
        result = []
        zone = find_or_create_zone(opts[:domain])

        # TODO: revert this when zerigo fog gets fixed to allow parameters 
        # hosts = fqdn ? (zone.records.all(:name => fqdn) rescue []) : zone.records.all
        hosts = zone.records.all
        hosts = hosts.select {|h| name = h.name || ''; name == opts[:host] } if opts.has_key?(:host) && opts[:host] != '*'
        hosts = hosts.select {|h| h.type == opts[:type] } if opts.has_key?(:type) && opts[:type] != '*'
        
        return hosts
      end

      def find_host_records(opts = {})
        hosts = find_hosts(opts)
        group = {}
        hosts.each do |h|
          key = "#{h.name}.#{h.domain} #{h.type}"
          group[key] ||= []
          group[key] << h
        end
        result = group.values.collect {|h| hosts_to_opts(h).merge(:domain => opts[:domain])}
        return result
      end

      def create_host_record(opts = {})
        opts = setup_opts(opts, [:host, :data, :domain, :type, :ttl])
        zone = find_or_create_zone(opts[:domain])
        opts_to_hosts(opts).each do |host|
          zone.records.create(host)
        end
      end

      def destroy_host_record(opts = {})
        opts = setup_opts(opts, [:host, :domain])

        find_hosts(opts).each do |h|
          h.destroy || raise("Failed to destroy #{h.hostname}")
        end
      end

      def update_host_record(old_opts={}, new_opts={})
        old_opts = setup_opts(old_opts, [:host, :domain, :type])
        new_opts = setup_opts(new_opts, [:host, :domain, :type, :data])

        # Tricky to update existing hosts since zerigo needs a separate host
        # entry for multiple records of same type (MX, etc), so take the easy
        # way out and destroy/create instead of update
        destroy_host_record(old_opts)
        create_host_record(new_opts)
      end

    end
    
  end
end
