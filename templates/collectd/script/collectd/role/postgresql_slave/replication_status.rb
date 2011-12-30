require 'pg'

master = Rubber.instances.for_role('postgresql_master').first.full_name
slave = "localhost"
opts = { :dbname => Rubber.config.db_name,
         :user => Rubber.config.db_user,
         :password => Rubber.config.db_pass }
mconn = PGconn.open(opts.merge({:host => master}))
sconn = PGconn.open(opts.merge({:host => slave}))

mval = mconn.exec("select pg_current_xlog_location()")[0]["pg_current_xlog_location"]
sresult = sconn.exec("select pg_last_xlog_receive_location(), pg_last_xlog_replay_location()")[0]
sval_receive = sresult["pg_last_xlog_receive_location"]
sval_replay = sresult["pg_last_xlog_replay_location"]


def numeric(val)
  # First part is logid, second part is record offset
  parts = val.split("/")
  raise "Invalid location" if parts.size != 2 && parts.any {|p| p.to_s.strip.size == 0}
  result = (0xFFFFFFFF * parts[0].to_i) + parts[1].to_i(16)
  return result
end


master_offset = numeric(mval)
receive_offset = numeric(sval_receive)
replay_offset = numeric(sval_replay)

puts "PUTVAL #{HOSTNAME}/postgresql/gauge-replication_receive_delay interval=#{INTERVAL} N:#{master_offset - receive_offset}"
puts "PUTVAL #{HOSTNAME}/postgresql/gauge-replication_replay_delay interval=#{INTERVAL} N:#{master_offset - replay_offset}"
