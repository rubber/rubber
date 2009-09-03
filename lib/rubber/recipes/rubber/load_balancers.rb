namespace :rubber do

  desc <<-DESC
    Sets up the network load balancers
  DESC
  required_task :setup_load_balancers do
    setup_load_balancers()
  end

  desc <<-DESC
    Describes the network load balancers
  DESC
  required_task :describe_load_balancers do
    lbs = cloud.describe_load_balancers()
    pp lbs
  end

  def setup_load_balancers
    # get remote lbs
    # for each local not in remote, add it
    #   get all zones for all instances for roles, and make sure in lb
    #   warn if lb not balanced (count of instances per zone is equal)
    # for each local that is in remote, sync listeners and zones
    # for each remote not in local, remove it
  end

end
