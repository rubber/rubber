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
        if creds[:provider] == 'aws'
          @name_includes_domain = true
          @name_includes_trailing_period = true
        end
      end
      
      def normalize_name(name, domain)
        domain = domain.gsub(/\.$/, "") if @name_includes_trailing_period

        name = name.gsub(/\.$/, "") if @name_includes_trailing_period
        name = name.gsub(/.?#{domain}$/, "") if @name_includes_domain
        
        return name, domain
      end
      
      def denormalize_name(name, domain)
        if @name_includes_domain
          if name && name.strip.empty?
            name = "#{domain}"
          else
            name = "#{name}.#{domain}"
          end
        end
        
        if @name_includes_trailing_period
          name = "#{name}." 
          domain = "#{domain}."
        end
        
        return name, domain
      end
      
      def host_to_opts(host)
        name, domain = normalize_name(host.name || '', host.zone.domain)
        opts = {}
        opts[:id] = host.id if host.respond_to?(:id) && host.id
        opts[:host] = fix_hostname(name)
        opts[:domain] = domain
        opts[:type] = host.type
        opts[:ttl] = host.ttl.to_i if host.ttl
        opts[:priority] = host.priority if host.respond_to?(:priority) && host.priority

        if host.respond_to?(:alias_target) && ! host.alias_target.nil?

          # Convert from camel-case to snake-case for Route 53 ALIAS records so the match the rubber config format.
          opts[:data] = {
            'hosted_zone_id' => host.alias_target['HostedZoneId'],
            'dns_name' => host.alias_target['DNSName'].split('.')[0..-1].join('.')
          }

          # Route 53 ALIAS records do not have a TTL, so delete the rubber-supplied default value.
          opts.delete(:ttl)
        else
          opts[:data] = Array(host.value).first if host.value
        end

        return opts
      end

      def opts_to_host(opts, host={})
        name, domain = denormalize_name(opts[:host], opts[:domain])

        host[:name] = name
        host[:type] =  opts[:type]
        host[:ttl] = opts[:ttl] if opts[:ttl]
        host[:priority] = opts[:priority] if opts[:priority]

        if opts[:data]
          creds = Rubber::Util.symbolize_keys(env.credentials)

          if creds[:provider] == 'aws'
            # Route 53 requires the priority to be munged with the data value.
            if opts[:type] =~ /MX/i
              host[:value] = "#{opts[:priority]} #{opts[:data]}"
            else
              # Route 53 allows creation of ALIAS records, which will always be a Hash in the DNS config.  ALIAS records
              # cannot have a TTL.
              if opts[:data].is_a?(Hash)
                host[:alias_target] = opts[:data]
                host.delete(:ttl)
              else
                host[:value] = opts[:data]
              end
            end
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

        # TODO: revert this when fog gets fixed
        # hosts = fqdn ? (zone.records.all(:name => fqdn) rescue []) : zone.records.all
        hosts = zone.records.all
        if fqdn
          hosts = hosts.find_all do |r|
            attributes = host_to_opts(r)

            # Route 53 encodes the asterisk character ('*') as octal.  Translate it here so rubber is consistent.
            host, domain = fix_hostname(attributes[:host]), attributes[:domain]
            
            fog_fqdn = ""
            fog_fqdn << "#{host}." if host && ! host.strip.empty?
            fog_fqdn << "#{domain}"
            
            fqdn == fog_fqdn
          end
        end

        hosts.each do |h|
          keep = true
          attributes = host_to_opts(h)

          if host_type && host_type != '*' && attributes[:type] != host_type
            keep = false
          end

          if host_data && attributes[:data] != host_data
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
          changes = opts_to_host(new_opts)
          result = nil
          if h.respond_to?(:modify)
            result = h.modify(changes)
          elsif h.respond_to?(:update_host)
            result = h.update_host(changes)
          else
            changes.each do |k, v|
              h.send("#{k}=", v)
            end
            result = h.save
          end

          result || raise("Failed to update host #{h.hostname}, #{h.errors.full_messages.join(', ')}")
        end
      end

      def fix_hostname(host)
        # Route 53 encodes asterisks in their ASCII octal representation.
        host.gsub("\\052", "*")
      end

    end

  end
end
