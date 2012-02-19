
namespace :rubber do

  namespace :resque do
  
    rubber.allow_optional_tasks(self)

    namespace :worker do

      rubber.allow_optional_tasks(self)

      before "deploy:stop", "rubber:resque:worker:stop"
      after "deploy:start", "rubber:resque:worker:start"
      after "deploy:restart", "rubber:resque:worker:restart"

      desc "Starts resque workers"
      task :start, :roles => :resque_worker do
        rsudo "service resque-pool start"
      end

      desc "Stops resque workers and monitor"
      task :stop, :roles => :resque_worker do
        rsudo "service resque-pool stop || true"
      end

      desc "Force kill all resque workers and monitor"
      task :force_stop, :roles => :resque_worker do
        rsudo "kill -TERM `cat #{rubber_env.resque_pool_pid_file}`"
      end

      desc "Restarts resque workers"
      task :restart, :roles => :resque_worker do
        stop
        start
      end

      desc "Continuously show worker stats"
      task :stats, :roles => :resque_worker do
        logger.level = 0

        WorkerItem = Struct.new(:host, :pid, :process_type, :target, :start_time)
        WorkerItem.class_eval do
          def uid
            "#{host}:#{pid}"
          end
        end

        mutex = Mutex.new

        while true do

          host_data = {}
          run "ps ax | grep '[r]esque.*:'; exit 0" do |channel, stream, data|
            if data
              host = channel.properties[:host].gsub(/\..*/, '')
              mutex.synchronize do
                host_data[host] ||= ""
                host_data[host] << data
              end
            end
          end

          queue_sizes = capture 'redis-cli --raw smembers resque:queues | while read x; do if [[ -z $x ]]; then continue; fi; echo -n "$x "; echo "llen resque:queue:$x" | redis-cli --raw; done', :roles => :redis
          queue_sizes = Hash[*queue_sizes.split]

          idle = []
          starting = []
          paused = []
          parents = []
          children = []

          host_data.each do |host, data|
            data.lines do |line|
              line.chomp!
              cols = line.split

              # 12887 ?        Sl     0:01 resque-1.13.0: Forked 31395 at 1300564431
              # 13054 ?        Sl     0:23 resque-1.13.0: Processing facebook since 1300565337
              # 28561 ?        Sl     0:03 resque-1.13.0: Waiting for *index*

              item = WorkerItem.new
              item.host = host
              item.pid = cols[0]
              item.process_type = case cols[5]
                when 'Processing' then :child
                when 'Forked' then :parent
                when 'Waiting' then (cols.delete_at(6); :idle)
                when 'Starting' then :starting
                when 'Paused' then :paused
                else :unknown
              end
              item.target = cols[6]
              item.start_time = cols[8].to_i

              idle << item if item.process_type == :idle
              starting << item if item.process_type == :starting
              paused << item if item.process_type == :paused
              parents << item if item.process_type == :parent
              children << item if item.process_type == :child
            end
          end

          pairs = {}
          (parents + children).each {|item| pairs[item.uid] ||= [];  pairs[item.uid] << item}
          stuck_parents = pairs.select{|item| item.size == 1 && item.first.type == :parent}
          stuck_children = pairs.select{|item| item.size == 1 && item.first.type == :child}

          print "\e[H\e[2J"
          puts Time.now
          puts ""

          counts = children.group_by {|item| item.target || 'unknown' }
          queue_sizes.each {|target, count| counts[target] ||= [] }

          fmt = "%-37s %-7s"
          puts fmt % ["Working", counts.values.collect(&:size).inject(0) { |sum, p| sum + p }]
          puts fmt % ["Idle", idle.size]
          puts fmt % ["Starting", starting.size]
          puts fmt % ["Paused", paused.size]
          puts fmt % ["Stuck Parents", stuck_parents.size]
          puts fmt % ["Orphans", stuck_children.size]

          puts ""
          fmt = "%-37s %-10s %-10s"
          puts fmt % %w{Queue Working Queued}
          counts.sort.each do |target, items|
            working = items.size
            queued = queue_sizes[target].to_i
            if working > 0 || queued > 0
              puts fmt % [target, working, queued]
            end
          end

          puts ""
          fmt = "%-10s %-6s"
          puts fmt % %w{Runtime Count}

          times = [1, 5, 15, 30, 60, 120]
          slow_times = [180, 540]
          ages = children.group_by do |item|
            runtime = Time.now.to_i - item.start_time
            runtime = 0 if item.start_time == 0
            (times + slow_times).find {|t| runtime < (t * 60)}
          end

          times.each do |t|
            items = ages[t] || []
            puts fmt % [t, items.size]
          end
          slow_times.each do |t|
            items = ages[t] || []
            slow_queues = items.collect(&:target).sort.uniq.join(', ')
            puts "#{fmt} %s" % ["#{t}", items.size, slow_queues]
          end
          slow_queues = (ages[nil] || []).collect(&:target).sort.uniq.join(', ')
          puts "#{fmt} %s" % [">#{slow_times.last}", (ages[nil] || []).size, slow_queues]

          sleep 10
        end
      end
      
    end

    namespace :web do
      rubber.allow_optional_tasks(self)
      
      before "deploy:stop", "rubber:resque:web:stop"
      after "deploy:start", "rubber:resque:web:start"
      after "deploy:restart", "rubber:resque:web:restart"

      desc "Starts resque web tools"
      task :start, :roles => :resque_web do
        rsudo "service resque-web start"
      end

      desc "Stops resque web tools"
      task :stop, :roles => :resque_web do
        rsudo "service resque-web stop || true"
      end

      desc "Restarts resque web tools"
      task :restart, :roles => :resque_web do
        stop
        start
      end

    end

  end
end
