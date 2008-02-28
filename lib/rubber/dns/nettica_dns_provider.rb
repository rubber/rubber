require 'nettica/client'

class NetticaDnsProvider < DynamicDnsBase

  def initialize(env)
    super(env)
    @client = Nettica::Client.new(env.dns_user, env.dns_password)
    @ttl = (env.dns_ttl || 300).to_i
    @record_type = env.dns_record_type || "A"
  end

  def nameserver
    "dns1.nettica.com"
  end

  def host_exists?(host)
    domain_info = @client.list_domain(env.domain)
    raise "Domain needs to exist in nettica before records can be updated" unless domain_info.record
    return domain_info.record.any? { |r| r.hostName == host }
  end

  def create_host_record(host, ip)
    new = @client.create_domain_record(env.domain, host, @record_type, ip, @ttl, 0)
    @client.add_record(new)
  end

  def destroy_host_record(host)
    old_record = @client.list_domain(env.domain).record.find {|r| r.hostName == host }
    old = @client.create_domain_record(env.domain, host, old_record.recordType, old_record.data, old_record.tTL, old_record.priority)
    @client.delete_record(old)
  end

  def update_host_record(host, ip)
    old_record = @client.list_domain(env.domain).record.find {|r| r.hostName == host }
    old = @client.create_domain_record(env.domain, host, old_record.recordType, old_record.data, old_record.tTL, old_record.priority)
    new = @client.create_domain_record(env.domain, host, @record_type, ip, @ttl, 0)
    @client.update_record(old, new)
  end

end
