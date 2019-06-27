class AutoscaleNotifier < ActionMailer::Base
  default :from => Rubber.config.admin_email

  def autoscale_failed_notification(to, message)
    @message = message
    @latest_logs = Resque.redis.lrange Rubber.config.autoscale_log_key, 0, 10
    mail(:to => to, :subject => 'Rubber Autoscale Failed')
  end

  def high_loading_notification(to)
    mail(:to => to, :subject => 'Rubber Autoscale High Loading')
  end

  def daily_report(to, graph_url)
    @url = graph_url
    @autoscale_status = Resque.redis.get(Rubber.config.autoscale_status_key).to_i
    @resque_info = Resque.info
    mail(:to => to, :subject => 'Rubber Autoscale Daily Report')
  end
end
