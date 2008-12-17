
namespace :rubber do

  namespace :passenger do
  
    rubber.allow_optional_tasks(self)
  
    after "rubber:install_packages", "rubber:passenger:custom_install"
    
    task :custom_install, :roles => :web do
      rubber.sudo_script 'install_passenger', <<-ENDSCRIPT
        wget -qP /tmp http://github.com/tarballs/FooBarWidget-passenger-151a33cc11d8753f5bd4cb0ec2cfee5008dbd840.tar.gz
        tar -C /tmp -xzf /tmp/FooBarWidget-passenger-151a33cc11d8753f5bd4cb0ec2cfee5008dbd840.tgz
        rake package:gem && gem install pkg/*gem --no-rdoc --no-ri
        echo -en "\n\n\n\n" | passenger-install-apache2-module
        wget -qP /tmp http://rubyforge.org/frs/download.php/41041/ruby-enterprise_1.8.6-20080810-i386.deb
        dpkg -i /tmp/ruby-enterprise_1.8.6-20080810-i386.deb
      ENDSCRIPT
    end
  end
end
