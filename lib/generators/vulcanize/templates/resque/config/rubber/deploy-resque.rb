
namespace :rubber do

  namespace :resque do
  
    rubber.allow_optional_tasks(self)
  
    after "rubber:install_packages", "rubber:resque:custom_install"
    
    task :custom_install, :roles => :resque do
      rubber.sudo_script 'install_resque', <<-ENDSCRIPT
        if [ -d resque ]; then
          rm -r resque
        fi

        git clone git://github.com/defunkt/resque.git

        if [ -d #{rubber_env.resque_web_dir} ]; then
          rm -r #{rubber_env.resque_web_dir}
        fi

        mkdir -p #{rubber_env.resque_web_dir}
        mkdir #{rubber_env.resque_web_dir}/tmp
        mv resque/config.ru #{rubber_env.resque_web_dir}
        mv resque/lib/resque/server/* #{rubber_env.resque_web_dir}/

        rm -f /var/www/resque
        ln -s #{rubber_env.resque_web_dir}/public /var/www/resque
      ENDSCRIPT
    end

    after "rubber:setup_app_permissions", "rubber:resque:setup_resque_permissions"

    task :setup_resque_permissions, :roles => :resque do
      rsudo "chown -R #{rubber_env.app_user}:#{rubber_env.app_user} #{rubber_env.resque_web_dir}/config.ru"
    end
    
  end
end
