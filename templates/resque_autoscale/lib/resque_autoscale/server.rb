require 'rubber'
require 'resque'
require 'sinatra/base'
require 'erb'
require 'google_visualr'

module ResqueAutoscale
  class Server < Sinatra::Base

    enable :sessions
    use Rack::Flash

    set :root, "#{File.dirname(File.expand_path(__FILE__))}/server"

    get "/" do
      redirect url(:reporting)
    end

    get "/configuration" do
      @current_page = "configuration"
      @lower_threshold = Resque.redis.get(Rubber.config.autoscale_lower_threshold_key) || Rubber.config.autoscale_lower_threshold_default
      @higher_threshold = Resque.redis.get(Rubber.config.autoscale_higher_threshold_key) || Rubber.config.autoscale_higher_threshold_default
      @instances_min = Resque.redis.get(Rubber.config.autoscale_instances_min_key) || Rubber.config.autoscale_instances_min_default
      @instances_max = Resque.redis.get(Rubber.config.autoscale_instances_max_key) || Rubber.config.autoscale_instances_max_default
      @admin_email = Resque.redis.get(Rubber.config.autoscale_admin_email_key)
      erb :configuration
    end

    post "/configuration" do
      if params['inputLowerThreshold']
        Resque.redis.set(Rubber.config.autoscale_lower_threshold_key, params['inputLowerThreshold'].to_i)
      end
      if params['inputHigherThreshold']
        Resque.redis.set(Rubber.config.autoscale_higher_threshold_key, params['inputHigherThreshold'].to_i)
      end
      if params['inputInstancesMin']
        Resque.redis.set(Rubber.config.autoscale_instances_min_key, params['inputInstancesMin'].to_i)
      end
      if params['inputInstancesMax']
        Resque.redis.set(Rubber.config.autoscale_instances_max_key, params['inputInstancesMax'].to_i)
      end
      if params['inputAdminEmail']
        Resque.redis.set(Rubber.config.autoscale_admin_email_key, params['inputAdminEmail'])
      end
      flash[:success] = "Autoscale configuration successfully updated" if params['inputLowerThreshold'] || params['inputHigherThreshold'] || params['inputInstancesMin'] || params['inputInstancesMax']
      redirect url(:configuration)
    end

    get "/operations" do
      @current_page = "operations"
      @worker_hosts = worker_hosts
      erb :operations
    end

    post "/operations" do
      if params['disableAutoscale']
        Resque.redis.set(Rubber.config.autoscale_status_key, 0)
        flash[:warning] = "Autoscale disabled!"
        log "Autoscale disabled!"
      end
      if params['enableAutoscale']
        Resque.redis.set(Rubber.config.autoscale_status_key, 1)
        flash[:success] = "Autoscale enabled!"
        log "Autoscale enabled!"
      end
      if params['clearLogs']
        Resque.redis.ltrim(Rubber.config.autoscale_log_key, 0, 0)
        flash[:success] = "Logs cleared!"
      end
      redirect url(:operations)
    end

    post "/add_worker" do
      if params['add_worker']
        if autoscale_status != 1
          flash[:error] = "Autoscale is not ready!"
        else
          flash[:error] = "Not supported currently!"
          #TODO need find way how invoke commands as root
          #system("bash -l -c \" #{Rubber.root}/script/rubber cron --rake autoscale:add_worker\" &> /dev/null &")
          #flash[:success] = "New instance creation was started!"
        end
        #start
      end
      redirect url(:operations)
    end

    post "/destroy_worker" do
      unless params['destroy_worker'] && params['instance_id']
        flash[:error] = "Instance id is not provided"
      end
      if autoscale_status != 1
        flash[:error] = "Autoscale is not ready!"
      else
        flash[:error] = "Not supported currently!"
        #TODO need find way how invoke commands as root
        #system("bash -l -c \"#{Rubber.root}/script/rubber cron --rake autoscale:destroy_worker instance_name=#{params['instance_id']}\" &> /dev/null &")
        #flash[:success] = "Instance destroying was started!"
      end
      redirect url(:operations)
    end

    get "/reporting" do
      @current_page = "reporting"
      statuses = Resque.redis.lrange Rubber.config.autoscale_statistics_key, 0, 288

      max_value = 0
      data_table = GoogleVisualr::DataTable.new
      # Add Column Headers
      data_table.new_column('datetime', 'Time' )
      data_table.new_column('number', 'Total Workers')
      data_table.new_column('number', 'Working Workers')

      statuses.each do |status|
        time,total_workers,working_workers = status.split(":")
        data_table.add_row([Time.at(time.to_i).utc, total_workers.to_i, working_workers.to_i])
        max_value = total_workers.to_i if total_workers.to_i >= max_value
      end

      option = {title: 'Workers Loading', hAxis: {title: 'Time'}, vAxis: {title: 'Number of Workers', maxValue: max_value+5}, height: 450, legend: {position: 'bottom'} }
      @chart = GoogleVisualr::Interactive::AreaChart.new(data_table, option)
      @latest_logs = Resque.redis.lrange Rubber.config.autoscale_log_key, 0, 100

      @resque_info = Resque.info
      erb :reporting
    end

    def worker_hosts
      hosts = Hash.new { [] }

      Resque.workers.each do |worker|
        host, _ = worker.to_s.split(':')
        hosts[host] += [worker.to_s]
      end

      hosts
    end

    def log(message)
      Resque.redis.lpush(Rubber.config.autoscale_log_key, "#{Time.now.to_i}:::#{message}")
      Resque.redis.ltrim(Rubber.config.autoscale_log_key, 0, 1000)
    end

    helpers do
      def flash_types
        [:success, :info, :warning, :error]
      end

      def autoscale_status
        Resque.redis.get(Rubber.config.autoscale_status_key).to_i
      end
    end

  end
end