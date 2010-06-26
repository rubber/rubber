module Rubber
  module Dns

    class Dyndns < Base

      def initialize(env)
        super(env, 'dyndns')
        @user, @pass = provider_env.user, provider_env.password
        @update_url = provider_env.update_url || 'https://members.dyndns.org/nic/update?hostname=%host%&myip=%ip%'
        @update_url = @update_url.gsub(/%([^%]+)%/, '#{\1}')
      end

      def nameserver
        "ns1.mydyndns.org"
      end

      def up_to_date(host, ip)
        # This queries dns server directly instead of using hosts file
        current_ip = nil
        Resolv::DNS.open(:nameserver => [nameserver], :search => [], :ndots => 1) do |dns|
          current_ip = dns.getaddress("#{host}.#{provider_env.domain}").to_s rescue nil
        end
        return ip == current_ip
      end
      
      def find_host_records(opts={})
        opts = setup_opts(opts, [:host, :domain])
        hostname = "#{opts[:host]}.#{opts[:domain]}"
        begin
          Resolv::DNS.open(:nameserver => [nameserver], :search => [], :ndots => 1) do |dns|
            r = dns.getresource(hostname, Resolv::DNS::Resource::IN::A)
            result = [{:host =>opts[:host], :data => r.address}]
          end
        rescue
          puts "Rescue #{e} #{e.message}"
          raise "Domain needs to exist in dyndns as an A record before record can be updated"
        end
      end

      def create_host_record(opts={})
        puts "WARNING: No create record available for dyndns, you need to do so manually"
      end

      def destroy_host_record(opts={})
        puts "WARNING: No destroy record available for dyndns, you need to do so manually"
      end

      def update_host_record(old_opts={}, new_opts={})
        old_opts = setup_opts(old_opts, [:host, :domain])

        host = "#{old_opts[:host]}.#{old_opts[:domain]}"
        ip = new_opts[:data]
        update_url = eval('%Q{' + @update_url + '}')
        # puts update_url
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
