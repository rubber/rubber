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
            mv -f /tmp/#{rubber_env.jdk}/* /usr/lib/jvm/jdk1.7/

            echo 'updating java alternative'
            update-alternatives --install "/usr/bin/java" "java" "/usr/lib/jvm/jdk1.7/bin/java" 1
            update-alternatives --install "/usr/bin/javac" "javac" "/usr/lib/jvm/jdk1.7/bin/javac" 1
            update-alternatives --install "/usr/bin/javaws" "javaws" "/usr/lib/jvm/jdk1.7/bin/javaws" 1

            echo 'installing tomcat'
            curl -o /tmp/apache-tomcat-7.0.34.tar.gz http://ftp.heanet.ie/mirrors/www.apache.org/dist/tomcat/tomcat-7/v7.0.34/bin/apache-tomcat-7.0.34.tar.gz
            tar -zxf /tmp/apache-tomcat-7.0.34.tar.gz -C #{rubber_env.tomcat_dest_folder}
            rm /tmp/apache-tomcat-7.0.34.tar.gz

            echo 'installing solr'
            curl -o /tmp/apache-solr-4.0.0.tgz http://ftp.heanet.ie/mirrors/www.apache.org/dist/lucene/solr/4.0.0/apache-solr-4.0.0.tgz
            tar -zxf /tmp/apache-solr-4.0.0.tgz -C /tmp
            cp /tmp/apache-solr-4.0.0/dist/apache-solr-4.0.0.war #{rubber_env.tomcat_dest_folder}/apache-tomcat-7.0.34/webapps/solr.war
            rm -fr /tmp/apache-solr-4.0.0*

            echo 'setting up solr'
            mkdir -p #{rubber_env.solr_home_dest_folder}/solr/data
            mkdir -p #{rubber_env.solr_home_dest_folder}/solr/#{rubber_env.core_name}
            tar -zxf /tmp/solr_conf.tar.gz -C /mnt/solr/#{rubber_env.core_name}
            mv /tmp/#{rubber_env.solr_xml} #{rubber_env.solr_home_dest_folder}/solr
            rm /tmp/solr_conf.tar.gz
          fi
        ENDSCRIPT
    end


    def set_java_opts
      "export JAVA_OPTS='-server -Xmx#{rubber_env.Xmx} -Dsolr.data.dir=#{rubber_env.solr_home_dest_folder}/solr/data -Dsolr.solr.home=#{rubber_env.solr_home_dest_folder}/solr'"
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
        echo 'stopping tomcat'
        #{set_java_opts}
        #{rubber_env.tomcat_dest_folder}/apache-tomcat-7.0.34/bin/shutdown.sh
      ENDSCRIPT
    end
  end

end
