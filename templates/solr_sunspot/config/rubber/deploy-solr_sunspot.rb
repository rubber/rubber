# installs, starts, stops and reindexes solr using the sunspot gem

namespace :rubber do

  namespace :solr_sunspot do

    desc "start solr"
    task :start, :roles => :solr_sunspot, :except => { :no_release => true } do 
      run "cd #{current_path} && RAILS_ENV=#{rails_env} bundle exec sunspot-solr start --port=8983 --data-directory=#{shared_path}/solr/data --pid-dir=#{shared_path}/pids"
    end
    desc "stop solr"
    task :stop, :roles => :solr_sunspot, :except => { :no_release => true } do 
      run "cd #{current_path} && RAILS_ENV=#{rails_env} bundle exec sunspot-solr stop --port=8983 --data-directory=#{shared_path}/solr/data --pid-dir=#{shared_path}/pids"
    end
    desc "reindex the whole database"
    task :reindex, :roles => :solr_sunspot do
      stop
      run "rm -rf #{shared_path}/solr/data"
      start
      run "cd #{current_path} && RAILS_ENV=#{rails_env} bundle exec rake sunspot:solr:reindex"
    end
    
    task :setup_solr_data_dir, :roles => :solr_sunspot  do
      run "mkdir -p #{shared_path}/solr/data"
    end

    after 'deploy:setup', 'rubber:solr_sunspot:setup_solr_data_dir'
  end
end

