namespace :rubber do
  desc <<-DESC
    Sets up the environment-wide VPC
  DESC

  required_task :setup_vpc do
    vpc_id = cloud.setup_vpc

    if vpc_id
      rubber_instances.artifact['vpc'] = vpc_id
      rubber_instances.save
    end
  end

  def get_vpc
    env = rubber_cfg.environment.bind(nil, [])
    
    env.rubber_instances.artifacts['vpc']   
  end
end

