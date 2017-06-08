namespace :rubber do

  namespace :squid do

    rubber.allow_optional_tasks(self)

    before "deploy:stop", "rubber:squid:stop"
    after "deploy:start", "rubber:squid:start"
    after "deploy:restart", "rubber:squid:reload"

    desc "Stops the squid"
    task :stop, :roles => :squid do
      rsudo "service squid3 stop || true"
    end

    desc "Starts the squid"
    task :start, :roles => :squid do
      rsudo "service squid3 start"
    end

    desc "Restarts the squid"
    task :restart, :roles => :squid do
      stop
      start
    end

    desc "Reload the squid"
    task :reload, :roles => :squid do
      rsudo "service squid3 reload"
    end

  end

end
