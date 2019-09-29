
namespace :rubber do

  namespace :filebeat do

    rubber.allow_optional_tasks(self)

    after "rubber:install_packages", "rubber:filebeat:install"
    after "rubber:install_packages", "rubber:filebeat:install_logz_certs"

    desc "Installs the filebeat service"
    task :install, :roles => :filebeat do
      rubber.sudo_script 'install', <<-ENDSCRIPT
        curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-5.0.2-amd64.deb
        dpkg -i filebeat-5.0.2-amd64.deb
      ENDSCRIPT
    end

    desc "Installs the logz.io certificates"
    task :install_logz_certs, :roles => :filebeat_logz do
      rubber.sudo_script 'install_logz', <<-ENDSCRIPT
      wget https://raw.githubusercontent.com/cloudflare/cfssl_trust/master/intermediate_ca/COMODORSADomainValidationSecureServerCA.crt
      mkdir -p /etc/pki/tls/certs
      cp COMODORSADomainValidationSecureServerCA.crt /etc/pki/tls/certs/
      ENDSCRIPT
    end

    after "rubber:bootstrap", "rubber:filebeat:bootstrap"
    task :bootstrap, :roles => :filebeat do
        rubber.update_code_for_bootstrap
        rubber.run_config(:file => "role/filebeat/", :force => true, :deploy_path => release_path)
        restart
    end

    desc "Start filebeat transfer system"
    task :start, :roles => :filebeat do
      rsudo 'service filebeat start'
    end

    desc "Stop filebeat transfer system"
    task :stop, :roles => :filebeat do
      rsudo 'service filebeat stop || true'
    end

    desc "Restart filebeat transfer system"
    task :restart, :roles => :filebeat do
      stop
      start
    end

    desc "Display status of filebeat transfer system"
    task :status, :roles => :filebeat do
      rsudo "service filebeat status || true"
    end

  end

end
