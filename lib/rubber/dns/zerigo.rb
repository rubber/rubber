require 'rubygems'
require 'httparty'

module Rubber
  module Dns


    class Zone
      include HTTParty
      format :xml

      def initialize(customer_id, email, token, domain)
        self.class.basic_auth email, token
        self.class.base_uri "https://ns.zerigo.com/accounts/#{customer_id}"
        @domain = domain
        refresh()
      end

      def hosts
        hosts = self.class.get("/zones/#{@zone['id']}/hosts.xml")
        return hosts['hosts']
      end

      def host(hostname)
        hosts = self.class.get("/zones/#{@zone['id']}/hosts.xml?fqdn=#{hostname}.#{@domain}")
        return (hosts['hosts'] || []).first
      end

      def new_host
        self.class.get("/zones/#{@zone['id']}/hosts/new.xml")['host']
      end

      def create_host(host)
        self.class.post("/zones/#{@zone['id']}/hosts.xml", :body => {:host => host})
      end

      def update_host(host)
        host_id = host['id']
        self.class.put("/zones/#{@zone['id']}/hosts/#{host_id}.xml", :body => {:host => host})
      end

      def delete_host(hostname)
        host_id = host(hostname)['id']
        self.class.delete("/zones/#{@zone['id']}/hosts/#{host_id}.xml")
      end

      def refresh
        zone_id = @zone['id'] rescue nil
        if zone_id
          @zone = self.class.get("/zones/#{zone_id}.xml")
        else
          zones = self.class.get('/zones.xml')
          @zone = zones["zones"].find {|z| z["domain"] == @domain }
        end
      end

      def data
        return @zone
      end

      protected

      def zones()
        self.class.get('/zones.xml')
      end

      def zone(domain_name)
        zone =  zones
        return zone
      end
      
    end
    
    class Zerigo < Base

      def initialize(env)
        super(env)
        @zerigo_env = env.dns_providers.zerigo
        @ttl = (@zerigo_env.ttl || 300).to_i
        @record_type = @zerigo_env.record_type || "A"
        @zone = Zone.new(@zerigo_env.customer_id, @zerigo_env.email, @zerigo_env.token, env.domain)
      end

      def nameserver
        "a.ns.zerigo.net"
      end

      def host_exists?(host)
        @zone.host(host)
      end

      def create_host_record(host, ip)
        host = @zone.new_host()
        host['host-type'] =  @record_type
        host['ttl'] = @ttl
        host['hostname'] = host
        host['data'] = ip
        @zone.create_host(host)
      end

      def destroy_host_record(host)
        @zone.delete_host(host)
      end

      def update_host_record(host, ip)
        old = @zone.host(host)
        old['data'] = ip
        @zone.update_host(old)
      end

      # update the top level domain record which has an empty hostName
      def update_domain_record(ip)
        old = @zone.hosts.find {|h| h['hostname'].nil? }
        old['data'] = ip
        @zone.update_host(old)
      end

    end

  end
end
