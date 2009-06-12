module Rubber
  module Dns

    class Dyndns < Base

      def initialize(env)
        super(env)
        @dyndns_env = env.dns_providers.dyndns
        @user, @pass = @dyndns_env.user, @dyndns_env.password
        @update_url = @dyndns_env.update_url || 'https://members.dyndns.org/nic/update?hostname=%host%&myip=%ip%'
        @update_url = @update_url.gsub(/%([^%]+)%/, '#{\1}')
      end

      def nameserver
        "ns1.mydyndns.org"
      end

      def host_exists?(host)
        begin
          Resolv::DNS.open(:nameserver => [nameserver], :search => [], :ndots => 1) do |dns|
            dns.getresource(hostname(host), Resolv::DNS::Resource::IN::A)
          end
        rescue
          raise "Domain needs to exist in dyndns as an A record before record can be updated"
        end
        return true
      end

      def create_host_record(host, ip)
        puts "WARNING: No create record available for dyndns, you need to do so manually"
      end

      def destroy_host_record(host)
        puts "WARNING: No destroy record available for dyndns, you need to do so manually"
      end

      def update_host_record(host, ip)
        host = hostname(host)
        update_url = eval('%Q{' + @update_url + '}')

        # This header is required by dyndns.org
        headers = {
         "User-Agent" => "Capistrano - Rubber - 0.1"
        }

        uri = URI.parse(update_url)
        http = Net::HTTP.new(uri.host, uri.port)
        # switch on SSL
        http.use_ssl = true if uri.scheme == "https"
        # suppress verification warning
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        req = Net::HTTP::Get.new(update_url.gsub(/.*:\/\/[^\/]*/, ''), headers)
        # authentication details
        req.basic_auth @user, @pass
        resp = http.request(req)
        # print out the response for the update
        puts "DynDNS Update result: #{resp.body}"
      end

    end

  end
end
