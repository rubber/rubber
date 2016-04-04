namespace :rubber do

  namespace :docker do
    before 'rubber:install_packages', 'rubber:base:setup_docker_apt_repository'
    task :setup_docker_apt_repository do
      rubber.sudo_script 'setup_docker_apt_repository', <<-ENDSCRIPT
        if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
          apt-key adv --keyserver hkp://pool.sks-keyservers.net:80 --recv-keys 58118E89F3A912897C070ADBF76221572C52609D
          echo "deb https://apt.dockerproject.org/repo ubuntu-trusty main" > /etc/apt/sources.list.d/docker.list
        fi
      ENDSCRIPT
    end

    before 'rubber:bootstrap', 'rubber:base:setup_docker_dirs'
    task :setup_docker_dirs do
      rubber.sudo_script 'update_sudoers', <<-ENDSCRIPT
        mkdir -p #{rubber_env.docker_tmp_dir}

        mkdir -p /root/.docker
      ENDSCRIPT
    end
  end

end