
namespace :rubber do
  
  namespace :mongodb do
    
    rubber.allow_optional_tasks(self)
    
    before "rubber:install_packages", "rubber:mongodb:setup_apt_sources"
  
    task :setup_apt_sources, :roles => :mongodb do
      # Setup apt sources to mongodb from 10gen
      sources = <<-SOURCES
        deb http://downloads-distro.mongodb.org/repo/ubuntu-upstart dist 10gen
      SOURCES
      sources.gsub!(/^[ \t]*/, '')
      put(sources, "/etc/apt/sources.list.d/mongodb.list") 
      rsudo "apt-key adv --keyserver keyserver.ubuntu.com --recv 7F0CEB10"
    end

    after "rubber:bootstrap", "rubber:mongodb:bootstrap"

    task :bootstrap, :roles => :mongodb do
      exists = capture("echo $(ls #{rubber_env.mongodb_data_dir} 2> /dev/null)")
      if exists.strip.size == 0
        rubber.update_code_for_bootstrap
        rubber.run_config(:file => "role/mongodb/", :force => true, :deploy_path => release_path)

        restart
      end
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
      rsudo "service mongodb stop || true"
    end
    
    desc <<-DESC
      Restarts the mongodb daemon
    DESC
    task :restart, :roles => :mongodb do
      stop
      start
    end

    desc <<-DESC
      Display status of the mongodb daemon
    DESC
    task :status, :roles => :mongodb do
      rsudo "service mongodb status || true"
      rsudo "ps -eopid,user,cmd | grep [m]ongod || true"
      rsudo "netstat -tupan | grep mongod || true"
    end

  end

end
