
namespace :rubber do

  namespace :passenger do

    rubber.allow_optional_tasks(self)

    before "rubber:install_packages", "rubber:passenger:setup_apt_sources"
    task :setup_apt_sources do
      rubber.sudo_script 'configure_passenger_nginx_repository', <<-ENDSCRIPT
        apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 561F9B9CAC40B2F7
        add-apt-repository -y https://oss-binaries.phusionpassenger.com/apt/passenger
      ENDSCRIPT
    end
    
    on :load do
      # serial_reload and serial_restart
      apache_serial_tasks = rubber.apache.tasks.values.select {|t| t.name =~ /^_serial_task_serial_/ }
      
      apache_serial_tasks.each do |apache_task|
        qualifier = apache_task.name.to_s.gsub(/^_serial_task_serial_/, '')
        remove_pool_name = "serial_remove_from_pool_#{qualifier}"
        add_pool_name = "serial_add_to_pool_#{qualifier}"
        
        task remove_pool_name.to_sym,
             search_task(:remove_from_pool).options.merge(:hosts => apache_task.options[:hosts]),
             &search_task(:remove_from_pool).body
        task add_pool_name.to_sym,
             search_task(:add_to_pool).options.merge(:hosts => apache_task.options[:hosts]),
             &search_task(:add_to_pool).body
        before apache_task.fully_qualified_name, "rubber:passenger:#{remove_pool_name}"
        after apache_task.fully_qualified_name, "rubber:passenger:#{add_pool_name}"
      end
    end
    
    before "rubber:apache:stop", "rubber:passenger:remove_from_pool"

    task :remove_from_pool, :roles => :passenger do
      maybe_sleep = " && sleep 5" if Rubber.env == 'production'
      rsudo "rm -f #{releases_path}/*/public/httpchk.txt#{maybe_sleep}"
    end
    
    after "rubber:apache:start", "rubber:passenger:add_to_pool"
    
    task :add_to_pool, :roles => :passenger do
      # Wait for passenger to startup before adding host back into haproxy pool
      logger.info "Waiting for passenger to startup"

      opts = get_host_options('rolling_restart_port') {|port| port.to_s}
      rsudo "while ! curl -s -f http://localhost:$CAPISTRANO:VAR$/ &> /dev/null; do echo .; done", opts
      rsudo "touch #{current_path}/public/httpchk.txt"
    end

    # passenger depends on apache for start/stop/restart, just need these defined
    # as apache hooks into standard deploy lifecycle

    deploy.task :restart, :roles => :passenger do
    end
    
    deploy.task :stop, :roles => :passenger do
    end
    
    deploy.task :start, :roles => :passenger do
    end
    
  end
end
