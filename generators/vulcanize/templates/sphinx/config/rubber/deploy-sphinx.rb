# installs, starts and stops sphinx searchd
#
# * make sure your app has installed a recent version of thinking sphinx
#   (released after Oct 13 2008). Older versions won't behave with rails 2.1
# * installation is ubuntu specific
# * start and stop tasks are using the thinking sphinx plugin

namespace :rubber do

  namespace :sphinx do
  
    rubber.allow_optional_tasks(self)
  
    after "rubber:install_packages", "rubber:sphinx:custom_install"
    
    task :custom_install, :roles => :sphinx do
      # install sphinx from source
      ver = "0.9.8-rc2"
      rubber.run_script 'install_sphinx', <<-ENDSCRIPT
        TMPDIR=`mktemp -d` || exit 1
        cd $TMPDIR
        wget -q http://www.sphinxsearch.com/downloads/sphinx-#{ver}.tar.gz
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

    after "deploy:restart", "rubber:sphinx:stop"
    after "deploy:restart", "rubber:sphinx:rebuild"
    after "deploy:restart", "rubber:sphinx:restart"

    # runs the given ultrasphinx rake tasks
    def run_sphinx task
      cmd = "cd #{current_path} && RAILS_ENV=#{RAILS_ENV} rake ts:"
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
      run_sphinx 'run'
    end
    
    desc "Configures and builds sphinx index"
    task :rebuild, :roles => :sphinx do
      run_sphinx 'config'
      run_sphinx 'index'
    end

  end

end
