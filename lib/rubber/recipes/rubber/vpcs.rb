namespace :rubber do
  desc <<-DESC
    Sets up the environment-wide VPC
  DESC

  required_task :setup_vpc do
    cloud.setup_vpc
  end

  required_task :destroy_vpc do
    env = rubber_cfg.environment.bind(nil, [])
    vpc_cfg = env.rubber_instances.artifacts['vpc']

    if vpc_cfg.length == 0
      fatal("No VPC configured", 0)
    end

    value = Capistrano::CLI.ui.ask("About to DESTROY #{vpc_cfg['id']} in mode #{Rubber.env}.  Are you SURE [yes/NO]?: ")

    fatal("Exiting", 0) if value != "yes"

    cloud.destroy_subnet(vpc_cfg['public_subnet'])
    cloud.destroy_subnet(vpc_cfg['private_subnet'])
    cloud.destroy_vpc(vpc_cfg['id'])

    env.rubber_instances.artifacts['vpc'] = {}
    env.rubber_instances.save
  end

  def get_vpc
    env = rubber_cfg.environment.bind(nil, [])

    env.rubber_instances.artifacts['vpc']
  end
end

