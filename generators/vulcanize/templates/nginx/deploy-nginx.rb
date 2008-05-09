
namespace :nginx do
  
  # serial_task can only be called after roles defined - not normally a problem, but
  # rubber auto-roles don't get defined till after all tasks are defined
  on :load do
    rubber.serial_task self, :serial_restart, :roles => :web do
      run "/etc/init.d/nginx restart"
    end
  end
  
  after "deploy:restart", "nginx:serial_restart"
  
  desc "Stops the nginx web server"
  task :stop, :roles => :web, :on_error => :continue do
    run "/etc/init.d/nginx stop"
  end
  
  desc "Starts the nginx web server"
  task :start, :roles => :web do
    run "/etc/init.d/nginx start"
  end
  
  desc "Retarts the nginx web server"
  task :restart, :roles => :web do
    serial_restart
  end

end
