module Rubber
  module Dns

    class Base

      attr_reader :env

      def initialize(env)
        @env = env   
      end

      def update(host, ip)
        if up_to_date(host, ip)
          puts "IP has not changed for #{host}, not updating dynamic DNS"
        else
          if find_host_records(:host => host).size == 0
            puts "Creating dynamic DNS: #{host} => #{ip}"
            create_host_record(:host => host, :data => [ip])
          else
            puts "Updating dynamic DNS: #{host} => #{ip}"
            update_host_record({:host => host}, {:host => host, :data => [ip]})
          end
        end
      end

      def destroy(host)
        if find_host_records(:host => host).size != 0
          puts "Destroying dynamic DNS record: #{host}"
          destroy_host_record(:host => host)
        end
      end

      def up_to_date(host, ip)
        find_host_records(:host => host).any? {|host| host[:data].include?(ip) }
      end

      def create_host_record(opts = {})
        raise "create_host_record not implemented"
      end

      def find_host_records(opts = {})
        raise "find_host_records not implemented"
      end

      def update_host_record(old_opts={}, new_opts={})
        raise "update_host_record not implemented"
      end

      def destroy_host_record(opts = {})
        raise "destroy_host_record not implemented"
      end

      def host_records_equal?(lhs_opts = {}, rhs_opts = {})
        lhs = setup_opts(lhs_opts)
        rhs = setup_opts(rhs_opts)
        [lhs, rhs].each {|h| h.delete(:id); h.delete(:priority) if h[:priority] == 0}
        lhs == rhs
      end

      def setup_opts(opts, required=[])
        default_opts = {:domain => env.domain || Rubber.config.domain,
                        :type => env['type'] || env.record_type || 'A',
                        :ttl => env.ttl || 300}
        
        if opts.delete(:no_defaults)
          actual_opts = Rubber::Util::symbolize_keys(opts)
        else
          actual_opts = default_opts.merge(Rubber::Util::symbolize_keys(opts))
        end

        if actual_opts.has_key?(:data) && actual_opts[:data].is_a?(Array) && actual_opts[:data].first.is_a?(Hash)
          actual_opts[:data] = actual_opts[:data].collect { |x| Rubber::Util.symbolize_keys(x) }
        end

        required.each do |r|
          raise "Missing required options: #{r}" unless actual_opts[r]
        end

        return actual_opts
      end
      

    end

  end
end
