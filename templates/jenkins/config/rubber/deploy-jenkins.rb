
namespace :rubber do
  
  namespace :jenkins do
    
    rubber.allow_optional_tasks(self)
    
    before "rubber:install_packages", "rubber:jenkins:setup_apt_sources"
  
    task :setup_apt_sources, :roles => :jenkins do
      # Setup apt sources to jenkins
      sources = <<-SOURCES
        deb http://pkg.jenkins-ci.org/debian binary/
      SOURCES
      sources.gsub!(/^[ \t]*/, '')
      put(sources, "/etc/apt/sources.list.d/jenkins.list") 
      rsudo "wget -q -O - http://pkg.jenkins-ci.org/debian/jenkins-ci.org.key | sudo apt-key add -"
    end

    after "rubber:bootstrap", "rubber:jenkins:bootstrap"

    task :bootstrap, :roles => :jenkins do
      exists = capture("echo $(ls /etc/apache2/jenkins.auth 2> /dev/null)")
      if exists.strip.size == 0
        rubber.update_code_for_bootstrap
        rubber.run_config(:file => "role/jenkins", :force => true, :deploy_path => release_path)

        restart
        rubber.apache.restart
        
        # user specific bootstrap (add plugins, etc)
        custom_bootstrap
      end
    end

    task :custom_bootstrap, :roles => :jenkins do
      jenkins_cli = "java -jar /var/cache/jenkins/war/WEB-INF/jenkins-cli.jar -s http://localhost:#{rubber_env.jenkins_proxy_port}/"
      
      rsudo "#{jenkins_cli} install-plugin -restart github"
      
      rubber.sudo_script 'configure_git', <<-ENDSCRIPT
        # Get host key for src machine to prevent ssh from failing
        rm -f #{jenkins_build_home}/.ssh/known_hosts
        ssh -o 'StrictHostKeyChecking=no' git@github.com &> /dev/null || true
      ENDSCRIPT
      #
      # Manual configuration steps in jenkins webui
      #
      # set github project (url for linking from build results): http://github.com/user/project/
      # set repository url to github clone address: git@github.com:user/project.git
      # set branches to build to: master
      # Under git advanced settings:
      #    Set Config user.name: jenkins
      #    Set Config user.email: jenkins@localhost
      # Set build command to:
      #    export RAILS_ENV=development
      #    bundle install --path $HOME/bundler
      #    bundle exec rake db:drop:all db:setup
      #    bundle exec rake
    end
    
    desc <<-DESC
      Starts the jenkins daemon
    DESC
    task :start, :roles => :jenkins do
      rsudo "service jenkins start"
    end
    
    desc <<-DESC
      Stops the jenkins daemon
    DESC
    task :stop, :roles => :jenkins do
      rsudo "service jenkins stop || true"
    end
    
    desc <<-DESC
      Restarts the jenkins daemon
    DESC
    task :restart, :roles => :jenkins do
      stop
      start
    end
    
  end

end
