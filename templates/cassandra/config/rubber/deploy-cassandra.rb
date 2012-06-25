
namespace :rubber do

  namespace :cassandra do
  
    rubber.allow_optional_tasks(self)
  
    after "rubber:install_packages", "rubber:cassandra:install"
    
    task :install, :roles => [:cassandra, :opscenter] do
      cassandra_dir_opts = get_host_options('cassandra_dir')
      cassandra_pkg_url_opts = get_host_options('cassandra_pkg_url')
      cassandra_version_opts = get_host_options('cassandra_version')
      cassandra_prefix_opts = get_host_options('cassandra_prefix')

      combined_opts = combine_opts cassandra_dir_opts, cassandra_pkg_url_opts, cassandra_version_opts, cassandra_prefix_opts

      install_script = <<-ENDSCRIPT
        cassandra_dir=$1
        cassandra_pkg_url=$2
        cassandra_version=$3
        cassandra_prefix=$4

        if [[ ! -d "$cassandra_dir" ]]; then
          wget -qNP /tmp $cassandra_pkg_url
          tar -C "$cassandra_prefix" -zxf /tmp/apache-cassandra-$cassandra_version-bin.tar.gz
          wget -qNO "$cassandra_dir/jmxterm.jar" http://downloads.sourceforge.net/project/cyclops-group/jmxterm/1.0-alpha-4/jmxterm-1.0-alpha-4-uber.jar
          wget --no-check-certificate -qNO "$cassandra_dir/lib/gelfj-0.9.1.jar" https://github.com/downloads/t0xa/gelfj/gelfj-0.9.1.jar
          wget --no-check-certificate -qNO "$cassandra_dir/lib/groovy-all-1.7.6.jar" https://github.com/pstehlik/gelf4j/raw/master/build/libs/groovy-all-1.7.6.jar
        fi
      ENDSCRIPT

      combined_opts[:script_args] = '$CAPISTRANO:VAR$'
      rubber.sudo_script 'install_cassandra', install_script, combined_opts

    end

    task :oldjdk_install, :roles => [:cassandra, :opscenter] do
      rubber.sudo_script 'install_cassandra', <<-ENDSCRIPT
        mkdir /tmp/jdk
        wget -qNP /tmp/jdk http://archive.canonical.com/pool/partner/s/sun-java6/sun-java6-jre_6.22-0ubuntu1~10.04_all.deb
        wget -qNP /tmp/jdk http://archive.canonical.com/pool/partner/s/sun-java6/sun-java6-bin_6.22-0ubuntu1~10.04_amd64.deb
        wget -qNP /tmp/jdk http://archive.canonical.com/pool/partner/s/sun-java6/sun-java6-jdk_6.22-0ubuntu1~10.04_amd64.deb
        dpkg -i /tmp/jdk/*.deb
      ENDSCRIPT
    end

    after "rubber:bootstrap", "rubber:cassandra:bootstrap"

    task :bootstrap, :roles => :cassandra do
      instances = rubber_instances.for_role("cassandra") & rubber_instances.filtered
      instances.each do |ic|
        task_name = "_bootstrap_cassandra_#{ic.full_name}".to_sym()
        task task_name, :hosts => ic.full_name do
          env = rubber_cfg.environment.bind("cassandra", ic.name)
          exists = capture("echo $(ls #{env.cassandra_data_dirs.first}/ 2> /dev/null)")
          if exists.strip.size == 0
            # Since no data dir, cleanup rest to make sure we start clean for a bootstrap
            #rsudo "rm -rf #{rubber_env.cassandra_data_dirs.join(" ")} #{rubber_env.saved_caches_dir} #{rubber_env.cassandra_commitlog_dir} #{rubber_env.cassandra_log_dir}"

            # After everything installed on machines, we need the source tree
            # on hosts in order to run rubber:config for bootstrapping the db
            rubber.update_code_for_bootstrap


            # Gen just the conf for cassandra
            rubber.run_config(:file => "role/cassandra/", :force => true, :deploy_path => release_path)
          end
        end
        send task_name
      end
    end

    def nodetool(*args)
      cassandra_dir_opts = get_host_options('cassandra_dir')
      cassandra_jmx_port_opts = get_host_options('cassandra_jmx_port')

      combined_opts = combine_opts cassandra_dir_opts,cassandra_jmx_port_opts

      nodetool_script = "$1/bin/nodetool --host localhost --port $2 #{args.join(' ')}"

      combined_opts[:script_args] = '$CAPISTRANO:VAR$'
      rubber.sudo_script 'run_nodetool', nodetool_script, combined_opts
    end

    def clustertool(*args)
      instances = rubber_instances.for_role("cassandra") & rubber_instances.filtered
      ic = instances.first
      task_name = "_clustertool_#{ic.full_name}_#{args.join('_')}".to_sym()
      task task_name, :hosts => ic.full_name do
        rsudo "#{rubber_env.cassandra_dir}/bin/clustertool --host $CAPISTRANO:HOST$ --port #{rubber_env.cassandra_jmx_port} #{args.join(' ')}"
      end
      send task_name
    end

    def jmxtool(*args)
      cassandra_dir_opts = get_host_options('cassandra_dir')
      cassandra_jmx_port_opts = get_host_options('cassandra_jmx_port')

      combined_opts = combine_opts cassandra_dir_opts,cassandra_jmx_port_opts

      jmxtool_script = "echo run -b #{args.join(' ')} | java -jar $1/jmxterm.jar -n -l #{ic.full_name}:$2"

      combined_opts[:script_args] = '$CAPISTRANO:VAR$'
      rubber.sudo_script 'run_jmx', jmxtool_script, combined_opts
    end

    def cassandra_stop
      opts = get_host_options('cassandra_pid_file')

      stop_script = "pid=`cat $1` && kill $pid; i=0; while ps $pid &> /dev/null; do sleep 1; (( i++ )); if (( i > 5 )); then kill -9 $pid; fi; done"
      opts[:script_args] = '$CAPISTRANO:VAR$'
      rubber.sudo_script 'stop_cassandra', stop_script, opts
    end

    def cassandra_start
      cassandra_dir_opts = get_host_options('cassandra_dir')
      cassandra_pid_file_opts = get_host_options('cassandra_pid_file')
      cassandra_log_dir_opts = get_host_options('cassandra_log_dir')

      combined_opts = combine_opts cassandra_dir_opts, cassandra_pid_file_opts, cassandra_log_dir_opts

      start_script = "nohup $1/bin/cassandra -p $2 &> $3/startup.log"

      combined_opts[:script_args] = '$CAPISTRANO:VAR$'

      rubber.sudo_script 'start_cassandra', start_script, combined_opts
    end

    def combine_opts(*opts_hashes)
      combined_opts = {}

      opts_hashes.each do |opts|
        opts.each do |key, value|
          if combined_opts[key]
            combined_opts[key] += " #{value}"
          else
            combined_opts[key] = value
          end
        end
      end

      combined_opts
    end

    task :restart, :roles => :cassandra do
      rubber.cassandra.stop
      rubber.cassandra.start
    end
    
    task :decommission, :roles => :cassandra do
      nodetool('decommission')
    end

    task :snapshot, :roles => :cassandra do
      nodetool('snapshot')
    end

    task :global_snapshot do
      clustertool('global_snapshot')
    end

    task :flush, :roles => :cassandra do
      nodetool('flush')
    end

    task :stop, :roles => :cassandra do
      cassandra_stop
    end

    task :start, :roles => :cassandra do
      cassandra_start
    end

    desc "Continuously show cassandra stats"
    task :tpstats_top, :roles => :cassandra do
      logger.level = 0
      fmt = "%-12s %-25s %-6s %-7s %s"
      while true do
        info = []
        run "#{rubber_env.cassandra_dir}/bin/nodetool --host $CAPISTRANO:HOST$ --port #{rubber_env.cassandra_jmx_port} tpstats | grep -v [C]ompleted$" do |channel, stream, data|
          if data
            host = channel.properties[:host].gsub(/\..*/, '')
            data.lines do |line|
              line.chomp!
              cols = line.split
              if cols[1].to_i > 0 || cols[2].to_i > 0
                info << [host, *cols]
              end
            end
          end
        end

        print "\e[H\e[2J"
        puts fmt % ["Host", "Pool Name", "Active", "Pending", "Completed"]
        info = info.sort {|a, b| c = a[1] <=> b[1]; c = a[0] <=> b[0] if c == 0; c }
        info.each do |i|
          puts fmt % i
        end

        sleep 1
      end
    end

    desc "Continuously show compaction stats"
    task :compactionstats_top, :roles => :cassandra do
      logger.level = 0
      fmt = "%-12s %-17s %-18s %-16s %-16s %s"
      info = {}
      run "#{rubber_env.cassandra_dir}/bin/nodetool -h $CAPISTRANO:HOST$ -p #{rubber_env.cassandra_jmx_port} compactionstats" do |channel, stream, data|
        if data
          host = channel.properties[:host].gsub(/\..*/, '')

          #compaction type: Validation
          #column family: LinkedinMetadata
          #bytes compacted: 0
          #bytes total in progress: 93442648
          #pending tasks: 4661

          info[host] ||= {}
          data.lines.each do |line|
            k, v = line.chomp.split(':')
            next if v.nil?
            
            k.strip!
            v.strip!
            
            if v =~ /\d+/
              v.gsub!(/(\d)(?=\d{3}+(?:\.|$))(\d{3}\..*)?/,'\1,\2')
            end
            if v =~ /Secondary index build/
              v = '2ary Index Build'
            end

            k = k.gsub(' ','_').to_sym

            if k == :column_family
              v = v.split('.').first
              v.gsub!('Metadata','')
            end
            
            info[host][k] = v

          end
        end
          
        print "\e[H\e[2J"
        puts fmt % ["Host", "Type", "Column Family", "Bytes Compacted", "Bytes Total", "Pending Tasks"]
        info.each do |host, i|
          next if i[:compaction_type] =~ /n\/a/ #&& i[:pending_tasks] == 0
          data = [host] + [:compaction_type, :column_family, :bytes_compacted, :bytes_total_in_progress, :pending_tasks].collect {|x| i[x]}
          puts fmt % data
        end
      end
    end

    desc "Dumps jmx stats for given pattern"
    task :jmxdump, :roles => :cassandra do
      args = ENV['PATTERN']
      rsudo "#{current_path}/script/jmxdump.rb #{args}"
    end


    desc "Live tail of cassandra log files for all machines"
    task :tail_logs, :roles => :cassandra do
      logger.level = 0
      grep = ENV['GREP']
      run "tail -qf #{rubber_env.cassandra_log_dir}/system.log #{'| grep ' + grep if grep}" do |channel, stream, data|
        host = channel.properties[:host].gsub(/\..*/, '')
        data.lines do |line|
          puts "#{host} #{line}"
        end
        break if stream == :err
      end
    end

    desc "Get cassandra log files for all machines"
    task :get_logs, :roles => :cassandra do
      tmp = "/tmp"
      basename = "cassandra_logs"
      tmpdir = "#{tmp}/#{basename}"
      tarfile = "#{tmp}/#{basename}.tgz"
      FileUtils.rm_f(tarfile)
      FileUtils.rm_rf(tmpdir)
      FileUtils.mkdir(tmpdir)
      
      download("#{rubber_env.cassandra_log_dir}/system.log", "#{tmpdir}/$CAPISTRANO:HOST$-system.log")
      system("tar -C '#{tmp}' -cvf '#{tarfile}' '#{basename}'")
    end

  end
end
