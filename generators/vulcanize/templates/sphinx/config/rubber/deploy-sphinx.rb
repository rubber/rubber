# installs, starts and stops sphinx
#
# Please note that all tasks are executed as runner. So sphinx will run under
# the same userid as mongrel. This is important to allow delta indexes (mongrel
# has to send a sighup to searchd).
#
# This means for you that you assure that runner can write to config/ log/ and
# db/sphinx. You may achieve this by simly executing a chown during deployment:
#
# before "rubber:pre_start", "setup_perms"
# before "rubber:pre_restart", "setup_perms"
#
# task :setup_perms do
#   run "find #{shared_path} -name cached-copy -prune -o -print | xargs  chown #{runner}:#{runner}"
#   run "chown -R #{runner}:#{runner} #{current_path}/"
# end
#
# * installation is ubuntu specific
# * start and stop tasks are using the thinking sphinx plugin

namespace :rubber do

  namespace :sphinx do
  
    rubber.allow_optional_tasks(self)
  
    after "rubber:install_packages", "rubber:sphinx:custom_install"
    
    task :custom_install, :roles => :sphinx do
      # install sphinx from source
      ver = "0.9.8.1"
      rubber.run_script 'install_sphinx', <<-ENDSCRIPT
        # check if already installed
        if [ -x /usr/local/bin/searchd ]
          then echo 'Found sphinx searchd on system'
          if /usr/local/bin/searchd --help | grep 'Sphinx #{ver}' 
            then echo 'Sphinx version matches, no further steps needed'
            exit 0
          fi
        fi
        
        echo 'Installing / Upgrading sphinx #{ver}'
        TMPDIR=`mktemp -d` || exit 1
        cd $TMPDIR
        echo 'Downloading'
        wget -q http://www.sphinxsearch.com/downloads/sphinx-#{ver}.tar.gz
        echo 'Unpacking'
        tar xf sphinx-#{ver}.tar.gz
        cd sphinx-#{ver}
        ./configure
        make
        make install
        cd ; rm -rf $TMPDIR
      ENDSCRIPT
    end
  
    before "deploy:stop", "rubber:sphinx:stop"

    after "deploy:start", "rubber:sphinx:rebuild"
    after "deploy:start", "rubber:sphinx:start"

    # ts:stop needs a valid config file so we have to create that before
    # restarting
    after "deploy:restart", "rubber:sphinx:config"
    after "deploy:restart", "rubber:sphinx:stop"
    after "deploy:restart", "rubber:sphinx:index"
    after "deploy:restart", "rubber:sphinx:start"

    # runs the given ultrasphinx rake tasks
    def run_sphinx task
      cmd = "cd #{current_path} && sudo -u #{runner} RAILS_ENV=#{RAILS_ENV} rake ts:"
      run cmd+task
    end

    
    desc "Stops sphinx searchd"
    task :stop, :roles => :sphinx, :on_error => :continue do
      run_sphinx 'stop'
    end
    
    desc "Starts sphinx searchd"
    task :start, :roles => :sphinx do
      run_sphinx 'run'
    end
    
    desc "Restarts sphinx searchd"
    task :restart, :roles => :sphinx do
      run_sphinx 'stop'
      run_sphinx 'start'
    end
    
    desc "Configures and builds sphinx index"
    task :rebuild, :roles => :sphinx do
      run_sphinx 'config'
      run_sphinx 'index'
    end

    desc "Configures sphinx index"
    task :config, :roles => :sphinx do
      run_sphinx 'config'
    end

    desc "Builds sphinx index"
    task :index, :roles => :sphinx do
      run_sphinx 'index'
    end

  end

end
