namespace :rubber do

  namespace :nodejs do

    rubber.allow_optional_tasks(self)

    before "rubber:install_packages", "rubber:nodejs:setup_apt_sources"

    desc "add nodejs repo"
    task :setup_apt_sources, roles: :nodejs do
      rsudo "apt-get install python-software-properties"
      rsudo "add-apt-repository ppa:chris-lea/node.js -y"
      rsudo "apt-get update"
    end

    after "rubber:bootstrap", "rubber:nodejs:update_nodejs_version"
    task :update_nodejs_version, roles: :nodejs do
      rsudo "npm cache clean -f"
      rsudo "npm install -g n"
      rsudo "sudo n 0.11.10"
    end

    before 'deploy:stop', 'rubber:nodejs:stop'
    after 'deploy:start', 'rubber:nodejs:start'
    after 'deploy:restart', 'rubber:nodejs:restart'

    before 'rubber:nodejs:start', 'rubber:nodejs:install'
    before 'rubber:nodejs:restart', 'rubber:nodejs:install'

    desc 'Installs npm dependencies for nodejs'
    task :install, roles: :nodejs do
      rsudo "cd #{current_path}/#{rubber_env.nodejs.app_dir}; npm install"
    end
    
    desc 'Starts the nodejs daemon'
    task :start, roles: :nodejs do
      rsudo "service nodejs start --force"
    end

    desc 'Stops the nodejs daemon'
    task :stop, roles: :nodejs do
      rsudo "service nodejs stop --force"
    end

    desc 'Hard kill the nodejs daemon, manually deleting pid and socket'
    task :kill, roles: :nodejs do
      rsudo "rm -r -f #{rubber_env.nodejs.pid_dir}/#{rubber_env.nodejs.pid_file} && pkill -9 -f '/bin/node '"
    end

    desc 'Restarts the nodejs daemon'
    task :restart, roles: :nodejs do
      rsudo "service nodejs restart --force"
    end

    desc 'Restarts the nodejs daemon'
    task :status, roles: :nodejs do
      rsudo "service nodejs status"
    end
  end
end
