namespace :rubber do

  namespace :java do

    before "rubber:install_packages", "rubber:java:setup_apt_sources"
    after  "rubber:install_packages", "rubber:java:update_alternatives"

    task :setup_apt_sources do
      release = capture("lsb_release -sc").strip
      sources = <<-SOURCES
        deb http://ppa.launchpad.net/webupd8team/java/ubuntu #{release} main 
        deb-src http://ppa.launchpad.net/webupd8team/java/ubuntu #{release} main 
      SOURCES
      sources.gsub!(/^ */, '')
      put(sources, "/etc/apt/sources.list.d/java.list")
      rsudo "apt-key adv --keyserver keyserver.ubuntu.com --recv-keys EEA14886"  
      rsudo "echo oracle-java7-installer shared/accepted-oracle-license-v1-1 select true | /usr/bin/debconf-set-selections"
    end

    task :update_alternatives do
      rsudo "update-java-alternatives -s java-7-oracle || true"
    end

  end

end
