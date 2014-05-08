namespace :rubber do

  namespace :hubot do

    rubber.allow_optional_tasks(self)

    after "rubber:node:install", "rubber:hubot:install"

    task :install, :roles => :hubot do
      rubber.run_script 'install_hubot', <<-ENDSCRIPT
      if [ ! -d "#{rubber_env.hubot_home}" ];then
        $(id  #{rubber_env.hubot_user} > /dev/null 2>&1)||useradd --shell /bin/false -M #{rubber_env.hubot_user}
        #{rubber_env.node_prefix}/bin/npm install -g coffee-script
        #{rubber_env.node_prefix}/bin/npm install -g hubot@#{rubber_env.hubot_version}
        cd #{rubber_env.hubot_prefix} && git clone #{rubber_env.hubot_git_url}
        #{rubber_env.node_prefix}/bin/npm install --save hubot-hipchat
      fi
      ENDSCRIPT
    end

    task :bootstrap, :roles => :hubot do
      rubber.run "cd #{rubber_env.hubot_home} && git pull"
      rubber.update_code_for_bootstrap
      rubber.run_config(:file => "role/hubot", :force => true, :deploy_path => release_path)
      restart
    end

    desc "Stop Hubot"
    task :stop, :roles => :hubot, :on_error => :continue do
      rsudo "service hubot stop || true"
    end

    desc "Start Hubot"
    task :start, :roles => :hubot do
      rsudo "service hubot start"
    end

    desc "Restart Hubot"
    task :restart, :roles => :hubot do
      stop
      start
    end

  end

end
