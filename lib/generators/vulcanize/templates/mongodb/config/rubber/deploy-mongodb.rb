
namespace :rubber do
  
  namespace :mongodb do
    
    rubber.allow_optional_tasks(self)
    
    before "rubber:install_packages", "rubber:mongodb:install"
    after "rubber:install_packages", "rubber:mongodb:setup_paths"
  
    task :install, :roles => :mongodb do
      # Setup apt sources to mongodb from 10gen
      sources = <<-SOURCES
        deb http://downloads-distro.mongodb.org/repo/ubuntu-upstart dist 10gen
      SOURCES
      sources.gsub!(/^ */, '')
      put(sources, "/etc/apt/sources.list.d/mongodb.list") 
      rsudo "apt-key adv --keyserver keyserver.ubuntu.com --recv 7F0CEB10"
    end
    
    task :setup_paths, :roles => :mongodb do
      rubber.sudo_script 'setup_mongodb_paths', <<-ENDSCRIPT
        if [[ ! -d "#{rubber_env.mongodb_data_dir}" ]]; then
          mkdir -p #{rubber_env.mongodb_data_dir}
          chown -R mongodb:mongodb #{rubber_env.mongodb_data_dir}
        fi
      ENDSCRIPT
    end
    
    desc <<-DESC
      Starts the mongodb daemon
    DESC
    task :start, :roles => :mongodb do
      rsudo "service mongodb start"
    end
    
    desc <<-DESC
      Stops the mongodb daemon
    DESC
    task :stop, :roles => :mongodb do
      rsudo "service mongodb stop"
    end
    
    desc <<-DESC
      Restarts the mongodb daemon
    DESC
    task :restart, :roles => :mongodb do
      rsudo "service mongodb restart"
    end
    
  end

end
