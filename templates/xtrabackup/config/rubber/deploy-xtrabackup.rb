namespace :rubber do
  
  namespace :xtrabackup do
    
    rubber.allow_optional_tasks(self)

    before "rubber:install_packages", "rubber:xtrabackup:add_repo"

    task :add_repo, :roles => [:percona, :mysql] do
      # Setup apt sources for percona
      codename = capture('lsb_release -c -s').chomp
      sources = <<-SOURCES
        deb http://repo.percona.com/apt #{codename} main
        deb-src http://repo.percona.com/apt #{codename} main
      SOURCES
      sources.gsub!(/^ */, '')
      put(sources, "/etc/apt/sources.list.d/percona.list") 
      rsudo "gpg --keyserver hkp://keys.gnupg.net --recv-keys 1C4CBDCDCD2EFD2A"
      rsudo "gpg -a --export CD2EFD2A | apt-key add -"
    end
    
  end
  
end