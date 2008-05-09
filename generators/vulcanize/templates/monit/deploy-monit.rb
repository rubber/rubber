
namespace :monit do
  
  # Put these first so monit gets shut down first
  before "deploy:stop", "monit:stop"
  before "deploy:restart", "monit:stop"
  
  # put these last so monit gets started last
  after "deploy:start", "monit:start"
  after "deploy:restart", "monit:start"
  
  desc "Start monit daemon monitoring"
  task :start do
    run "/etc/init.d/monit start"
  end
  
  desc "Stop monit daemon monitoring"
  task :stop, :on_error => :continue do
    run "/etc/init.d/monit stop"
  end
  
  desc "Restart monit daemon monitoring"
  task :restart do
    stop_monit
    start_monit
  end

end

