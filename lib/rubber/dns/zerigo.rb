require 'rubygems'
require 'httparty'

module Rubber
  module Dns


    class Zone
      include HTTParty
      format :xml

      @@zones = {}
      def self.get_zone(domain, provider_env)
       @@zones[domain] ||= Zone.new(provider_env.customer_id, provider_env.email, provider_env.token, domain)
      end

      def initialize(customer_id, email, token, domain)
        self.class.basic_auth email, token
        self.class.base_uri "https://ns.zerigo.com/accounts/#{customer_id}"
        @domain = domain
        refresh()
      end

      def check_status(response)
        code = response.code
        if code < 200 || code > 299
          msg = "Failed to access zerigo api (http_status=#{code})"
          msg += ", check dns_providers.zerigo.customer_id/email/token in rubber.yml" if code == 401
          raise msg
        end
        return response
      end

      def create_host(opts)
        host = opts_to_host(opts, new_host())
        check_status self.class.post("/zones/#{@zone['id']}/hosts.xml", :body => {:host => host})
      end

      def find_host_records(opts={})
        result = []
        hn = opts[:host]
        ht = opts[:type]
        hd = opts[:data]
        has_host = hn && hn != '*'

        url = "/zones/#{@zone['id']}/hosts.xml"
        if has_host
          url << "?fqdn="
          url << "#{hn}." if hn.strip.size > 0
          url << "#{@domain}"
        end
        hosts = self.class.get(url)

        # returns 404 on not found, so don't check status
        hosts = check_status hosts unless has_host

        hosts['hosts'].each do |h|
          keep = true
          if ht && h['host_type'] != ht && ht != '*'
            keep = false
          end
          if hd && h['data'] != hd
            keep = false
          end
          result << host_to_opts(h) if keep
        end if hosts['hosts']

        return result
      end

      def update_host(host_id, opts)
        host = opts_to_host(opts, new_host())
        check_status self.class.put("/zones/#{@zone['id']}/hosts/#{host_id}.xml", :body => {:host => host})
      end

      def delete_host(host_id)
        check_status self.class.delete("/zones/#{@zone['id']}/hosts/#{host_id}.xml")
      end

      def refresh
        zone_id = @zone['id'] rescue nil
        if zone_id
          @zone = check_status self.class.get("/zones/#{zone_id}.xml")
        else
          zones = check_status self.class.get('/zones.xml')
          @zone = zones["zones"].find {|z| z["domain"] == @domain }
        end
        if ! @zone
          zone = new_zone()
          zone['domain'] = @domain
          zones = check_status self.class.post('/zones.xml', :body => {:zone => zone})
          @zone = zones['zone']
        end
      end

      def zone_record
        return @zone
      end

      private

      def new_host
        check_status(self.class.get("/zones/#{@zone['id']}/hosts/new.xml"))['host']
      end

      def new_zone
        check_status(self.class.get("/zones/new.xml"))['zone']
      end

      def opts_to_host(opts, host={})
        host['hostname'] = opts[:host]
        host['host_type'] =  opts[:type]
        host['data'] = opts[:data] if opts[:data]
        host['ttl'] = opts[:ttl] if opts[:ttl]
        host['priority'] = opts[:priority] if opts[:priority]
        return host
      end

      def host_to_opts(host)
        opts = {}
        opts[:id] = host['id'] 
        opts[:domain] = @domain
        opts[:host] = host['hostname'] || ''
        opts[:type] = host['host_type']
        opts[:data] = host['data'] if host['data']
        opts[:ttl] = host['ttl'] if host['ttl']
        opts[:priority] = host['priority'] if host['priority']
        return opts
      end
    end
    
    class Zerigo < Base

      def initialize(env)
        super(env, "zerigo")
      end

      def find_host_records(opts = {})
        opts = setup_opts(opts, [:host, :domain])
        zone = Zone.get_zone(opts[:domain], provider_env)

        zone.find_host_records(opts)
      end

      def create_host_record(opts = {})
        opts = setup_opts(opts, [:host, :data, :domain, :type, :ttl])
        zone = Zone.get_zone(opts[:domain], provider_env)

        zone.create_host(opts)
      end

      def destroy_host_record(opts = {})
        opts = setup_opts(opts, [:host, :domain])
        zone = Zone.get_zone(opts[:domain], provider_env)

        find_host_records(opts).each do |h|
          zone.delete_host(h[:id])
        end
      end

      def update_host_record(old_opts={}, new_opts={})
        old_opts = setup_opts(old_opts, [:host, :domain])
        new_opts = setup_opts(new_opts.merge(:no_defaults =>true), [])
        zone = Zone.get_zone(old_opts[:domain], provider_env)

        find_host_records(old_opts).each do |h|
          zone.update_host(h[:id], h.merge(new_opts))
        end
      end

    end

  end
end
