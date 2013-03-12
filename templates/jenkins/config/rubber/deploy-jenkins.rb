
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

    after "rubber:apache:bootstrap", "rubber:jenkins:bootstrap"

    task :bootstrap, :roles => :jenkins do
      exists = capture("echo $(ls /etc/apache2/jenkins.auth 2> /dev/null)")
      if exists.strip.size == 0
        rubber.update_code_for_bootstrap
        rubber.run_config(:file => "role/jenkins", :force => true, :deploy_path => release_path)

        restart
        rubber.apache.restart

        # user specific bootstrap (add plugins, etc)
        sleep(5) # Allow Jenkins enough time to start up.
        custom_bootstrap
      end
    end

    task :custom_bootstrap, :roles => :jenkins do
      jenkins_cli = "java -jar /var/cache/jenkins/war/WEB-INF/jenkins-cli.jar -s http://localhost:#{rubber_env.jenkins_proxy_port}/"

      rubber.sudo_script "update_jenkins_plugin_list", <<-ENDSCRIPT
        curl -L http://updates.jenkins-ci.org/update-center.json | sed '1d;$d' | curl -X POST -H "Accept: application/json" -d @- http://localhost:#{rubber_env.jenkins_proxy_port}/updateCenter/byId/default/postBack
      ENDSCRIPT

      rsudo "#{jenkins_cli} install-plugin github"
      rsudo "#{jenkins_cli} install-plugin gravatar"
      rsudo "#{jenkins_cli} install-plugin brakeman"
      rsudo "#{jenkins_cli} install-plugin rubyMetrics"
      rsudo "#{jenkins_cli} install-plugin xvfb"
      rsudo "#{jenkins_cli} restart"

      init_jenkins_user_ssh = <<-ENDSCRIPT
        # Get host key for src machine to prevent ssh from failing
        rm -f #{rubber_env.jenkins_build_home}/.ssh/known_hosts
        ssh -o 'StrictHostKeyChecking=no' git@github.com &> /dev/null || true
      ENDSCRIPT

      rubber.sudo_script 'configure_git', init_jenkins_user_ssh, :as => "jenkins"

      #
      # Manual configuration steps in jenkins webui
      #
      # Set discard old builds (7 days?)
      # Set email notification
      # set github project (url for linking from build results): http://github.com/user/project/
      # set repository url to github clone address: git@github.com:user/project.git
      # set branches to build to: master
      # Check Build when a change is pushed to GitHub
      #   (add https://jenkins.host/github-webhook/ to github post receive hook on github project)
      # Set build command to:
      #    ./script/ci_test.sh
      # Check Publish JUnit test result report, xmls: test/reports/*.xml
      # Check Publish Rcov report, directory: coverage/rcov
    end

    desc <<-DESC
      Starts the jenkins daemon
    DESC
    task :start, :roles => :jenkins do
      rsudo "service jenkins status || service jenkins start"
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
