
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
  end
end
