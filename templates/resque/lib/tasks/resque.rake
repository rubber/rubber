require 'resque/pool/tasks'

# this task will get called before resque:pool:setup
# and preload the rails environment in the pool manager
task "resque:setup" => :environment do
  # generic worker setup, e.g. Airbrake for failed jobs
end

task "resque:pool:setup" do
  # close any sockets or files in pool manager
  ActiveRecord::Base.connection.disconnect!
  
  # and re-open them in the resque worker parent
  Resque::Pool.after_prefork do |job|
    ActiveRecord::Base.establish_connection
    Resque.redis = YAML.load_file(Rails.root.join('config', 'resque.yml'))[Rails.env]

    NewRelic::Agent.after_fork(:force_reconnect => true) if defined?(NewRelic)
  end
end
