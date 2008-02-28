class DynamicDnsBase

  def self.get_provider(provider, env)
    require("#{File.dirname(__FILE__)}/#{provider}_dns_provider.rb")
    clazz = Kernel.const_get(provider.capitalize + "DnsProvider")
    return clazz.new(env)
  end

  attr_reader :env

  def initialize(env)
    @env = env
  end

  def update(host, ip)
    if up_to_date(host, ip)
      puts "IP has not changed for #{host}, not updating dynamic DNS"
    else
      if ! host_exists?(host)
        puts "Creating dynamic DNS: #{host} => #{ip}"
        create_host_record(host, ip)
      else
        puts "Updating dynamic DNS: #{host} => #{ip}"
        update_host_record(host, ip)
      end
    end
  end

  def destroy(host)
    if host_exists?(host)
      puts "Destroying dynamic DNS record: #{host}"
      destroy_host_record(host)
    end
  end

  def hostname(host)
    "#{host}.#{env.domain}"
  end

  def up_to_date(host, ip)
    # This queries dns server directly instead of using hosts file
    current_ip = nil
    Resolv::DNS.open(:nameserver => [nameserver], :search => [], :ndots => 1) do |dns|
      current_ip = dns.getaddress(hostname(host)).to_s rescue nil
    end
    return ip == current_ip
  end

  def nameserver()
    raise "nameserver not implemented"
  end

  def host_exists?(host)
    raise "host_exists? not implemented"
  end

  def create_host_record(host, ip)
    raise "create_host_record not implemented"
  end

  def destroy_host_record(host)
    raise "destroy_host_record not implemented"
  end

  def update_host_record(host, ip)
    raise "update_host_record not implemented"
  end

end


