
namespace :rubber do
  
  namespace :mysql_proxy do
    
    rubber.allow_optional_tasks(self)

    # mysql-proxy needs to get stopped last and started first so that 
    # other processes that use db aren't affected
    after "deploy:stop", "rubber:mysql_proxy:stop"
    before "deploy:start", "rubber:mysql_proxy:start"
    before "deploy:restart", "rubber:mysql_proxy:restart"
      
    before "rubber:install_packages", "rubber:mysql_proxy:install"
  
    task :install do
      # Setup apt sources to getmysql-proxy (needs to happen for all roles)
      # https://launchpad.net/~mysql-cge-testing/+archive
      #      
      sources = <<-SOURCES
         deb http://ppa.launchpad.net/ndb-bindings/ubuntu hardy main
         deb-src http://ppa.launchpad.net/ndb-bindings/ubuntu hardy main
      SOURCES
      sources.gsub!(/^ */, '')
      put(sources, "/etc/apt/sources.list.d/mysql_proxy.list")
    end
    
    desc <<-DESC
      Starts the mysql proxy daemon
    DESC
    task :start do
      rsudo "service mysql-proxy start"
    end
    
    desc <<-DESC
      Stops the mysql proxy daemon
    DESC
    task :stop do
      rsudo "service mysql-proxy stop"
    end
    
    desc <<-DESC
      Restarts the mysql proxy daemon
    DESC
    task :restart do
      rsudo "service mysql-proxy restart"
    end
    
    
  end

end
