# installs, starts and stops sphinx
#
# Please note that all tasks are executed as runner. So sphinx will run under
# the same userid as mongrel. This is important to allow delta indexes (mongrel
# has to send a sighup to searchd).
#
# * installation is ubuntu specific
# * start and stop tasks are using the thinking sphinx plugin

namespace :rubber do

  namespace :sphinx do

    rubber.allow_optional_tasks(self)

    after "rubber:install_packages", "rubber:sphinx:custom_install"

    task :custom_install, :roles => :sphinx do
      # install sphinx from source
      ver = "2.0.6"
      rubber.sudo_script 'install_sphinx', <<-ENDSCRIPT
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
        wget -qN http://sphinxsearch.com/files/sphinx-#{ver}-release.tar.gz
        echo 'Unpacking'
        tar xf sphinx-#{ver}-release.tar.gz
        cd sphinx-#{ver}-release
        ./configure
        make
        make install
        cd ; rm -rf $TMPDIR
      ENDSCRIPT
    end

    set :sphinx_root, Proc.new {"#{shared_path}/sphinx"}
    after "deploy:setup", "rubber:sphinx:setup"
    after "deploy:symlink", "rubber:sphinx:config_dir"

    before "deploy:stop", "rubber:sphinx:stop"
    after "deploy:start", "rubber:sphinx:start"
    after "deploy:restart", "rubber:sphinx:restart"
    before "deploy:cold" do
      before "rubber:sphinx:start", "rubber:sphinx:index"
    end
    before "rubber:create_staging" do
      before "rubber:sphinx:start", "rubber:sphinx:index"
    end

    desc "Do sphinx setup tasks"
    task :setup, :roles => :sphinx do
      # Setup links to sphinx config/index as they need to persist between deploys
      rsudo "mkdir -p #{sphinx_root} #{sphinx_root}/config #{sphinx_root}/db"
      rsudo "chown -R #{runner}:#{runner} #{sphinx_root}"
    end

    desc "Setup paths for sphinx runtime"
    task :config_dir, :roles => :sphinx do
      rsudo "rm -rf #{current_path}/sphinx"
      rsudo "ln -sf #{sphinx_root} #{current_path}/sphinx"
    end

    # runs the given ultrasphinx rake tasks
    def run_sphinx task
      rsudo "cd #{current_path} && RAILS_ENV=#{Rubber.env} #{fetch(:rake, 'rake')} #{task}", :as => runner
    end


    desc "Stops sphinx searchd"
    task :stop, :roles => :sphinx do
      run_sphinx 'ts:stop; exit 0'
    end

    desc "Starts sphinx searchd"
    task :start, :roles => :sphinx do
      # rake tasks that load rails env can be slow, so
      # do multiple here as a performance tweak
      # config always needs to be run before start as
      # rubber generates a sphinx config file with new paths
      run_sphinx 'ts:config ts:start'
    end

    desc "Restarts sphinx searchd"
    task :restart, :roles => :sphinx do
      # rake tasks that load rails env can be slow, so
      # do multiple here as a performance tweak
      run_sphinx 'ts:config ts:stop ts:start'
    end

    desc "Configures sphinx index"
    task :config, :roles => :sphinx do
      run_sphinx 'ts:config'
    end

    desc "Builds sphinx index"
    task :index, :roles => :sphinx do
      run_sphinx 'ts:index'
    end

  end

end
