require 'rubygems'
require 'fog'

module Rubber
  module Dns

    class Aws < Base

      attr_accessor :client

      def initialize(env)
        super(env)
        creds = { :provider => 'aws', :aws_access_key_id => env.access_key, :aws_secret_access_key => env.access_secret }
        @client = ::Fog::DNS.new(creds)
      end
      
      def normalize_name(name, domain)
        domain = domain.gsub(/\.$/, "")

        if name
          name = name.gsub(/\.$/, "")
          name = name.gsub(/.?#{domain}$/, "")
          # Route 53 encodes asterisks in their ASCII octal representation.
          name = name.gsub("\\052", "*")
        end
        
        return name, domain
      end
      
      def denormalize_name(name, domain)
        if ! name || name.strip.empty?
          name = "#{domain}"
        else
          name = "#{name}.#{domain}"
        end

        name = "#{name}." 
        domain = "#{domain}."
        
        return name, domain
      end
      
      # Convert from fog/aws model to rubber option hash that represents a dns record
      def host_to_opts(host)
        opts = {}
        
        opts[:host] ||= host.name || ''
        opts[:domain] ||= host.zone.domain
        opts[:host], opts[:domain] = normalize_name(opts[:host], opts[:domain])
        
        opts[:type] ||= host.type
        opts[:ttl] ||= host.ttl.to_i if host.ttl
        
        opts[:data] ||= []
        if host.type =~ /MX/i
          host.value.each do |val|
            parts = val.split(" ")
            opts[:data] << {'priority' => parts[0], 'value' => parts[1]}
          end
        elsif ! host.alias_target.nil?
          # Convert from camel-case to snake-case for Route 53 ALIAS records
          # so the match the rubber config format.
          opts[:data] << {
            'hosted_zone_id' => host.alias_target['HostedZoneId'],
            'dns_name' => host.alias_target['DNSName'].split('.')[0..-1].join('.')
          }
          # Route 53 ALIAS records do not have a TTL, so delete the rubber-supplied default value.
          opts.delete(:ttl)
        else
          opts[:data].concat(Array(host.value))
        end

        return opts
      end

      # Convert from rubber option hash that represents a dns record to fog/aws model 
      def opts_to_host(opts)
        host = {}
        host[:name], domain = denormalize_name(opts[:host], opts[:domain])
        
        host[:type] =  opts[:type]
        host[:ttl] = opts[:ttl] if opts[:ttl]

        if opts[:data]
          # Route 53 requires the priority to be munged with the data value.
          if host[:type] =~ /MX/i
            host[:value] = opts[:data].collect {|o| "#{o[:priority]} #{o[:value]}"}
          elsif opts[:data].first.is_a?(Hash)
            # Route 53 allows creation of ALIAS records, which will always be
            # a Hash in the DNS config.  ALIAS records cannot have a TTL.
            host[:alias_target] = opts[:data].first
            host.delete(:value)
            host.delete(:ttl)
          else
            host[:value] = opts[:data]
          end
        end

        return host
      end

      def find_or_create_zone(domain)
        zone = @client.zones.all.find {|z| z.domain =~ /^#{domain}\.?/}
        if ! zone
          zone = @client.zones.create(:domain => domain)
        end
        return zone
      end
      
      def all_hosts(zone)
        hosts = []
        opts = {}
        has_more = true
        
        while has_more
          all_hosts = zone.records.all(opts)
          has_more = all_hosts.is_truncated
          opts = {:name => all_hosts.next_record_name,
                  :type => all_hosts.next_record_type
          }
          hosts.concat(all_hosts)
        end
        
        return hosts        
      end
      
      
      def find_hosts(opts = {})
        opts = setup_opts(opts, [:host, :domain])
        result = []
        zone = find_or_create_zone(opts[:domain])
        host = opts_to_host(opts)
        
        if opts[:host] && opts[:host] != '*'
          found_host = zone.records.all(:name => host[:name], :type => host[:type], :max_items => 1).first
          found_host = nil if found_host && found_host.name != "#{host[:name]}." && found_host.type != host[:type]
          hosts = Array(found_host)
        else
          hosts = all_hosts(zone)
        end
        
        hosts = hosts.select {|h| h.name == host[:name] } if opts.has_key?(:host) && opts[:host] != '*'
        hosts = hosts.select {|h| h.type == host[:type] } if opts.has_key?(:type) && opts[:type] != '*'
        
        return hosts
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
        old_opts = setup_opts(old_opts, [:host, :domain, :type])
        new_opts = setup_opts(new_opts, [:host, :domain, :type, :data])
        new_host = opts_to_host(new_opts)

        host = find_hosts(old_opts).first
        result = host.modify(new_host)
        result || raise("Failed to update host #{host.name}, #{host.errors.full_messages.join(', ')}")
      end
      
    end

  end
end
