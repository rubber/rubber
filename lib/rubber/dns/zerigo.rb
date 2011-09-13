require 'rubygems'

begin
  require 'zerigo_dns'
rescue LoadError
  puts "Missing the zerigo_dns gem.  Install with `sudo gem install zerigo_dns`."
  raise
end

module Rubber
  module Dns

    class Zerigo < Base

      def initialize(env)
        super(env, "zerigo")

        ::Zerigo::DNS::Base.user = provider_env.email
        ::Zerigo::DNS::Base.password = provider_env.token
      end

      def host_to_opts(host)
        opts = {}
        opts[:id] = host.id
        opts[:host] = host.hostname || ''
        opts[:type] = host.host_type
        opts[:data] = host.data if host.data
        opts[:ttl] = host.ttl if host.ttl
        opts[:priority] = host.priority if host.priority
        return opts
      end

      def opts_to_host(opts, host={})
        host['hostname'] = opts[:host]
        host['host_type'] =  opts[:type]
        host['data'] = opts[:data] if opts[:data]
        host['ttl'] = opts[:ttl] if opts[:ttl]
        host['priority'] = opts[:priority] if opts[:priority]
        return host
      end

      def find_hosts(opts = {})
        opts = setup_opts(opts, [:host, :domain])
        result = []
        zone = ::Zerigo::DNS::Zone.find_or_create(opts[:domain])
        params = { :zone_id => zone.id }

        hn = opts[:host]
        ht = opts[:type]
        hd = opts[:data]
        has_host = hn && hn != '*'
        if has_host
          url = ""
          url << "#{hn}." if hn.strip.size > 0
          url << "#{opts[:domain]}"
          params[:fqdn] = url
        end

        begin
          hosts = ::Zerigo::DNS::Host.find(:all, :params=> params)

          hosts.each do |h|
            keep = true
            if ht && h.host_type != ht && ht != '*'
              keep = false
            end
            if hd && h.data != hd
              keep = false
            end
            result << h if keep
          end if hosts
        rescue ActiveResource::ResourceNotFound => e
        end

        return result
      end

      def find_host_records(opts = {})
        hosts = find_hosts(opts)
        result = hosts.collect {|h| host_to_opts(h).merge(:domain => opts[:domain]) }
        return result
      end

      def create_host_record(opts = {})
        opts = setup_opts(opts, [:host, :data, :domain, :type, :ttl])
        zone = ::Zerigo::DNS::Zone.find_or_create(opts[:domain])
        ::Zerigo::DNS::Host.create(opts_to_host(opts).merge(:zone_id => zone.id))
      end

      def destroy_host_record(opts = {})
        opts = setup_opts(opts, [:host, :domain])
        zone = ::Zerigo::DNS::Zone.find_or_create(opts[:domain])

        find_hosts(opts).each do |h|
          h.destroy || raise("Failed to destroy #{h.hostname}")
        end
      end

      def update_host_record(old_opts={}, new_opts={})
        old_opts = setup_opts(old_opts, [:host, :domain])
        new_opts = setup_opts(new_opts, [:host, :domain, :type, :data])
        zone = ::Zerigo::DNS::Zone.find_or_create(old_opts[:domain])

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
