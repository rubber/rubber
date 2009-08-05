
namespace :rubber do

  namespace :passenger do
  
    rubber.allow_optional_tasks(self)
  
    after "rubber:base:install_rubygems", "rubber:passenger:custom_install"
    
    task :custom_install, :roles => :web do
      rubber.sudo_script 'install_passenger', <<-ENDSCRIPT
        echo -en "\n\n\n\n" | passenger-install-apache2-module
        wget -q http://rubyforge.org/frs/download.php/58679/ruby-enterprise_1.8.6-20090610_i386.deb
        dpkg -i ruby-enterprise_1.8.6-20090610_i386.deb
        # enable needed apache modules / disable ubuntu default site
        #a2enmod rewrite
        #a2dissite default
      ENDSCRIPT
    end
    
    # serial_task can only be called after roles defined - not normally a problem, but
    # rubber auto-roles don't get defined till after all tasks are defined
    on :load do
      rubber.serial_task self, :serial_restart, :roles => :web do
        run "/etc/init.d/apache2 restart"
      end
      rubber.serial_task self, :serial_reload, :roles => :web do
        run "if ! ps ax | grep -v grep | grep -c apache2 &> /dev/null; then /etc/init.d/apache2 start; else /etc/init.d/apache2 reload; fi"
      end
    end
    
    desc "Stops the apache web server"
    task :stop, :roles => :web, :on_error => :continue do
      run "/etc/init.d/apache2 stop"
    end
    
    desc "Starts the apache web server"
    task :start, :roles => :web do
      run "/etc/init.d/apache2 start"
    end
    
    desc "Restarts the apache web server"
    task :restart, :roles => :web do
      serial_restart
    end
  
    desc "Reloads the apache web server"
    task :reload, :roles => :web do
      serial_reload
    end
    
  end
end
