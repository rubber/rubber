# installs, starts and stops solr
#
# * installation is ubuntu specific
# * start and stop tasks are using the thinking sphinx plugin

namespace :rubber do

  namespace :solr do

    rubber.allow_optional_tasks(self)

    after "rubber:install_packages", "rubber:solr:custom_install"

    desc "custom installing java and solr"
    task :custom_install, :roles => :solr do

        upload rubber_env.jdk_path, "/tmp/#{rubber_env.jdk}"
        upload rubber_env.solr_xml_path, "/tmp/#{rubber_env.solr_xml}"
        upload rubber_env.tarz_config_files, "/tmp/solr_conf.tar.gz"
        rubber.sudo_script 'install_java_solr', <<-ENDSCRIPT
        if [ ! -d "/usr/lib/jvm/jdk1.7" ]; then
                    echo 'installing oracle java'
                    tar -zxf /tmp/#{rubber_env.jdk} -C /tmp
                    sudo mkdir -p /usr/lib/jvm/jdk1.7
                    mv -f /tmp/jdk1.7.0_10/* /usr/lib/jvm/jdk1.7/

                    echo 'updating java alterlative'
                    update-alternatives --install "/usr/bin/java" "java" "/usr/lib/jvm/jdk1.7/bin/java" 1
                    update-alternatives --install "/usr/bin/javac" "javac" "/usr/lib/jvm/jdk1.7/bin/javac" 1
                    update-alternatives --install "/usr/bin/javaws" "javaws" "/usr/lib/jvm/jdk1.7/bin/javaws" 1
                    echo 'installing tomcat'
                    curl -o /tmp/#{tomcat_tar_file_name} #{rubber_env.tomcat_download_url}
                    tar -zxf /tmp/#{tomcat_tar_file_name} -C #{rubber_env.tomcat_dest_folder}
                    rm /tmp/#{tomcat_tar_file_name}

                    echo 'installing solr'
                    curl -o /tmp/#{solr_tar_file_name} #{rubber_env.solr_download_url}
                    tar -zxf /tmp/#{solr_tar_file_name} -C /tmp
                    cp /tmp/#{rubber_env.solr_untar_folder_name}/dist/#{rubber_env.solr_untar_folder_name}.war /mnt/#{rubber_env.tomcat_untar_folder_name}/webapps/solr.war
                    rm -fr /tmp/#{rubber_env.solr_untar_folder_name}*

                    echo 'setting up solr'
                    mkdir -p #{rubber_env.solr_home_dest_foler}/solr/data
                    mkdir -p #{rubber_env.solr_home_dest_foler}/solr/#{rubber_env.core_name}
                    tar -zxf /tmp/solr_conf.tar.gz -C /mnt/solr/#{rubber_env.core_name}
                    mv /tmp/#{rubber_env.solr_xml} #{rubber_env.solr_home_dest_foler}/solr
                    rm /tmp/solr_conf.tar.gz
              fi
              ENDSCRIPT
    end


    def set_java_opts
      "export JAVA_OPTS='-server -Xmx#{rubber_env.xmx} -Dsolr.data.dir=#{rubber_env.solr_home_dest_foler}/solr/data -Dsolr.solr.home=#{rubber_env.solr_home_dest_foler}/solr'"
    end

    desc "start solr"
    task :start_solr, :roles => :solr  do
      rubber.sudo_script 'start_solr', <<-ENDSCRIPT
        echo 'starting tomcat'
        #{set_java_opts}
        nohup #{rubber_env.tomcat_dest_folder}/apache-tomcat-7.0.34/bin/startup.sh  &
        sleep 5
      ENDSCRIPT
    end

    desc "stop solr"
    task :stop_solr, :roles => :solr do
      rubber.sudo_script 'stop_solr', <<-ENDSCRIPT
        echo 'stoping tomcat'
        #{set_java_opts}
        #{rubber_env.tomcat_dest_folder}/apache-tomcat-7.0.34/bin/shutdown.sh
      ENDSCRIPT
    end
  end

end
