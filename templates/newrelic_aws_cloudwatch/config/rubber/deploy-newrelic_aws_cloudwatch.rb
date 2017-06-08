#https://github.com/newrelic-platform/newrelic_aws_cloudwatch_plugin
namespace :rubber do
  namespace :newrelic_aws_cloudwatch do

    rubber.allow_optional_tasks(self)

    after "rubber:install_packages", "rubber:newrelic_aws_cloudwatch:install"

    task :install, :roles => :newrelic_aws_cloudwatch do
      #todo check installed version?
      rubber.sudo_script 'install_newrelic_aws_cloudwatch', <<-ENDSCRIPT
      cw=`pwd`

      wget https://github.com/newrelic-platform/newrelic_aws_cloudwatch_plugin/archive/latest.tar.gz
      mkdir -p #{rubber_env.newrelic_aws_cloudwatch_home}

      tar -zxf latest.tar.gz
      dir=(newrelic_aws_cloudwatch_plugin*)
      nr_dir=${dir[@]:0:1}
      cp -a $nr_dir/* #{rubber_env.newrelic_aws_cloudwatch_home}/
      cd #{rubber_env.newrelic_aws_cloudwatch_home}
      bundle install

      cd $cw
      rm -r $nr_dir
      rm latest.tar.gz
      ENDSCRIPT
    end

    before "deploy:stop", "rubber:newrelic_aws_cloudwatch:stop"
    after "deploy:start", "rubber:newrelic_aws_cloudwatch:start"
    after "deploy:restart", "rubber:newrelic_aws_cloudwatch:restart"

    desc "Stops the newrelic_aws_cloudwatch"
    task :stop, :roles => :newrelic_aws_cloudwatch do
      rsudo "service newrelic_aws_cloudwatch stop || true"
    end

    desc "Starts the newrelic_aws_cloudwatch"
    task :start, :roles => :newrelic_aws_cloudwatch do
      rsudo "service newrelic_aws_cloudwatch start"
    end

    desc "Restarts the newrelic_aws_cloudwatch"
    task :restart, :roles => :newrelic_aws_cloudwatch do
      stop
      start
    end

  end
end
