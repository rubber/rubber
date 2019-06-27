namespace :autoscale do

  #autoscale Status codes
  AUTOSCALE_DISABLED = 0
  AUTOSCALE_IDLE = 1
  CREATING_NEW_INSTANCE = 2
  BOOTSTRAPING = 3
  DEPLOYING = 4
  STOPPING_WORKERS = 5
  DESTROYING_INSTANCE = 6

  desc "Run autoscale"
  task :run  => :environment do
    check_loading
  end

  desc "Bring up new worker instance"
  task :add_worker  => :environment do
    check_autoscale_status
    bring_up_new_instance
  end

  desc "Destroy worker instance"
  task :destroy_worker  => :environment do
    check_autoscale_status
    unless ENV['instance_name']
      log "Destroying failed. Please provide instance name"
      fail
    end
    destroy_instance(ENV['instance_name'])
  end

  desc "Save worker statistics"
  task :save_worker_statistics => :environment do
    #TODO use Resque.info
    total_workers = Resque.workers.reject {|w| w.to_s !~ /:\*/}
    working_workers = total_workers.reject{|w| ! w.working?}

    Resque.redis.lpush(Rubber.config.autoscale_statistics_key, "#{Time.now.to_i}:#{total_workers.count}:#{working_workers.count}")
    Resque.redis.ltrim(Rubber.config.autoscale_statistics_key, 0, 5000)
  end

  desc "Send daily report notification"
  task :send_daily_report  => :environment do
     daily_report
  end

  def check_loading
    check_autoscale_status

    log "Checking workers loading"

    #TODO use Resque.info
    total_workers = Resque.workers.reject {|w| w.to_s !~ /:\*/}
    working_workers = total_workers.reject{|w| ! w.working?}
    loading = (working_workers.count.to_f/total_workers.count.to_f)*100 rescue 0
    log "Current loading is #{loading}%"

    if loading >= higher_threshold
      log "Loading is more than upper threshold #{higher_threshold}%"
      worker_instances = Rubber.config.rubber_instances.for_role("resque_worker")
      if worker_instances.count >= max_number_of_instances
        log "MAX allowed(#{max_number_of_instances}) number of resque_worker instances reached."
        notify_about_loading
        return
      else
        bring_up_new_instance
      end
    elsif loading <= lower_threshold
      log "Loading is less than lower threshold #{lower_threshold}%"
      worker_instances = Rubber.config.rubber_instances.for_role("resque_worker")
      if worker_instances.count <= min_number_of_instances
        log "MIN number(#{min_number_of_instances}) of resque_worker instance reached"
        return
      else
        worker_names = worker_instances.map &:name
        latest_worker = worker_names.sort.last.to_s
        destroy_instance(latest_worker)
      end
    else
      log "Loading is normal"
    end
  end

  def bring_up_new_instance
    update_status(CREATING_NEW_INSTANCE)

    #Name template worker01 worker10
    worker_instances = Rubber.config.rubber_instances.for_role("resque_worker")
    worker_names = worker_instances.map &:name
    latest_worker = worker_names.sort.last.to_s

    #worker name prefix
    prefix = Rubber.config.autoscale_worker_name_prefix
    new_id = latest_worker.gsub(prefix, "").to_i
    new_id += 1
    new_worker_name = new_id >= 10 ? "#{prefix}#{new_id}" : "#{prefix}0#{new_id}"
    begin
      log "bringing up new worker instance #{new_worker_name}"
      #STEP1 Bringing up new instance
      env = Rubber.env
      begin
        rubber_create(env, new_worker_name)
      rescue
        log "Instance creation failed. Retrying in 300 seconds..."
        sleep 300
        log "Trying to destroy failed instance"
        rubber_destroy(env, new_worker_name) rescue nil
        sleep 10
        log "Creating instance. Attempt #2"
        rubber_create(env, new_worker_name)
      end


      #STEP2 Bootstrap
      begin
        update_status(BOOTSTRAPING)
        rubber_bootstrap(env, new_worker_name)
      rescue
        log "Bootstrap failed. Retrying in 30 seconds..."
        sleep 30
        rubber_bootstrap(env, new_worker_name)
      end

      #STEP3 Deploy
      begin
        update_status(DEPLOYING)
        rubber_deploy(env, new_worker_name)
      rescue
        log "Deploy failed. Retrying in 30 seconds..."
        sleep 30
        rubber_deploy(env, new_worker_name)
      end

      log "Instance #{new_worker_name} was successfully created"
      complete
    rescue Exception => e
      log e.message
      disable!
      notify_about_error(e.message)
    end
  end

  def destroy_instance(instance_name)
    begin
      env = Rubber.env

      #all resque workers instances using prefix 'worker'.
      #worker01, worker02....
      #check name here
      raise "Wrong instance name #{instance_name}" unless instance_name =~ /#{Rubber.config.autoscale_worker_name_prefix}/

      log "Destroying worker instance #{instance_name}"

      update_status(STOPPING_WORKERS)
      #STEP 1 stopping monit for that instance
      log "RAILS_ENV=#{env} FILTER=#{instance_name} cap rubber:monit:stop"
      res = system({"RAILS_ENV" => env, "FILTER" => instance_name}, "cap rubber:monit:stop")
      #log results
      raise "Failed!!! cap rubber:monit:stop" unless res

      #STEP 2 stopping resque workers for that instance
      log "RAILS_ENV=#{env} FILTER=#{instance_name} cap rubber:resque:worker:stop"
      res = system({"RAILS_ENV" => env, "FILTER" => instance_name}, "cap rubber:resque:worker:stop")
      #log results
      raise "Failed!!! rubber:resque:worker:stop" unless res

      log "Waiting while all workers will be stopped"
      loop do
        workers = Resque.workers.reject {|w| w.to_s !~ /#{instance_name}/}
        if workers.blank?
          log "all workers for instance #{instance_name} were stopped"
          break
        else
          log "#{workers.count} workers left...."
          sleep 15
        end
      end

      #STEP 3 removing instance
      begin
        update_status(DESTROYING_INSTANCE)
        rubber_destroy(env, instance_name)
      rescue
        log "Destroy failed. Retrying in 30 seconds..."
        sleep 30
        rubber_destroy(env, instance_name)
      end

      log "Instance #{instance_name} was successfully destroyed"
      complete
    rescue Exception => e
      log e.message
      disable!
      notify_about_error(e.message)
    end
  end

  def rubber_create(env, worker_name)
    timeout(10.minutes) do
      log "RAILS_ENV=#{env} ALIAS=#{worker_name} ROLES=resque_worker cap rubber:create"
      res = system({"RAILS_ENV" => env, "ALIAS" => worker_name, "ROLES"=> "resque_worker"}, "cap rubber:create")
      raise "Failed!!!  cap rubber:create" unless res
    end
  end

  def rubber_bootstrap(env, worker_name)
    timeout(15.minutes) do
      log "RAILS_ENV=#{env} FILTER=#{worker_name} cap rubber:bootstrap"
      res = system({"RAILS_ENV" => env, "FILTER" => worker_name }, "cap rubber:bootstrap")
      raise "Failed!!! cap rubber:autoscale_bootstrap" unless res
    end
  end

  def rubber_deploy(env, worker_name)
    timeout(10.minutes) do
      log "RAILS_ENV=#{env} FILTER=#{worker_name} cap deploy"
      res = system({"RAILS_ENV" => env, "FILTER" => worker_name}, "cap deploy")
      raise "Failed!!! cap deploy" unless res
    end
  end

  def rubber_destroy(env, worker_name)
    timeout(120.minutes) do
      log "RAILS_ENV=#{env} ALIAS=#{worker_name} FORCE=yes cap rubber:destroy"
      res = system({"RAILS_ENV" => env, "ALIAS" => worker_name, "FORCE" => "yes"}, "cap rubber:destroy")
      raise "Failed!!! cap rubber:destroy" unless res
    end
  end

  def update_status(status)
    Resque.redis.set(Rubber.config.autoscale_status_key, status)
  end

  def complete
    #log "Autoscale completed"
    update_status(AUTOSCALE_IDLE)
  end

  def disable!
    log "Autoscale disabled"
    update_status(AUTOSCALE_DISABLED)
  end

  def log(message)
    puts message
    Resque.redis.lpush(Rubber.config.autoscale_log_key, "#{Time.now.to_i}:::#{message}")
    Resque.redis.ltrim(Rubber.config.autoscale_log_key, 0, 1000)
  end

  def check_autoscale_status
    status = Resque.redis.get(Rubber.config.autoscale_status_key).to_i
    case status
      when AUTOSCALE_DISABLED
        log "Autoscale is currently disabled."
        fail
      when AUTOSCALE_IDLE
        #log "Starting"
      else
        log "Autoscale is in progress."
        fail
    end
  end

  def lower_threshold
    Resque.redis.get(Rubber.config.autoscale_lower_threshold_key).to_i  ||=  Rubber.config.autoscale_lower_threshold_default
  end

  def higher_threshold
    Resque.redis.get(Rubber.config.autoscale_higher_threshold_key).to_i  ||=  Rubber.config.autoscale_higher_threshold_default
  end

  def min_number_of_instances
    Resque.redis.get(Rubber.config.autoscale_instances_min_key).to_i  ||=  Rubber.config.autoscale_instances_min_default
  end

  def max_number_of_instances
    Resque.redis.get(Rubber.config.autoscale_instances_max_key).to_i  ||=  Rubber.config.autoscale_instances_max_default
  end

  def notify_about_error(message)
    admin_email = Resque.redis.get(Rubber.config.autoscale_admin_email_key)
    return unless admin_email.present?
    log "Sending error notification."
    AutoscaleNotifier.deliver_autoscale_failed_notification(admin_email, message)
  end

  def notify_about_loading
    admin_email = Resque.redis.get(Rubber.config.autoscale_admin_email_key)
    return unless admin_email.present?
    log "Sending high loading notification."
    AutoscaleNotifier.deliver_high_loading_notification(admin_email)
  end

  def daily_report
    admin_email = Resque.redis.get(Rubber.config.autoscale_admin_email_key)
    return unless admin_email.present?
    log "Sending daily report."
    statuses = Resque.redis.lrange Rubber.config.autoscale_statistics_key, 0, 288
    data = []
    start_time = nil
    end_time = nil
    statuses.each do |status|
      time,total_workers,working_workers = status.split(":")
      data << (working_workers.to_f/total_workers.to_f)*100
      end_time = time.to_i unless end_time
      start_time = time.to_i
    end
    time_labels = []
    (start_time..end_time).step(3600*4) do |hour|
      time_labels << Time.at(hour).strftime("%b %d %H:%M")
    end
    #Generating graph url for email
    url = Gchart.line(:title => "Workers Loading",
                       :data => data.reverse,
                       :size => '900x300',
                       :bar_colors => 'DC3912',
                       :axis_with_labels => 'x,y',
                       :axis_labels => [time_labels, 0.step(100,10).map{|x| "#{x}%"}])+"&chm=B,C8A2AB,0,0,0&chf=c,s,C1D1EF&chg=10,10,10,1"

    AutoscaleNotifier.deliver_daily_report(admin_email, url)
  end

end