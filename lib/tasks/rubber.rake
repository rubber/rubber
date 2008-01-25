namespace :rubber do

  if ENV['NO_ENV']
    $:.unshift "#{File.dirname(__FILE__)}/.."
  end

  desc "Generate system config files by transforming the files in the config tree"
  task :config => ENV['NO_ENV'] ? [] : [:environment] do
    require 'socket'
    instance_alias = Socket::gethostname.gsub(/\..*/, '')

    require 'rubber/configuration'
    cfg = Rubber::Configuration.get_configuration(ENV['RAILS_ENV'])
    instance = cfg.instance[instance_alias]
    if instance
      roles = instance.roles.collect{|role| role.name}
    elsif RAILS_ENV == 'development'
      roles = cfg.environment.known_roles
      instance = Rubber::Configuration::InstanceItem.new(instance_alias, roles, nil)
      cfg.instance.add(instance)
    end

    gen = Rubber::Configuration::Generator.new('config/rubber', roles, instance_alias)
    if ENV['NO_POST']
      gen.no_post = true
    end
    if ENV['FILE']
      gen.file_pattern = ENV['FILE']
    end
    gen.run

  end

end
