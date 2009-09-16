namespace :rubber do

  #desc <<-DESC
  #  Sets up the network load balancers
  #DESC
  #required_task :setup_load_balancers do
  #  setup_load_balancers()
  #end
  #
  #desc <<-DESC
  #  Describes the network load balancers
  #DESC
  #required_task :describe_load_balancers do
  #  lbs = cloud.describe_load_balancers()
  #  pp lbs
  #end

  def setup_load_balancers
    # OPTIONAL: Automatically provision and assign instances to a Cloud provided
    # load balancer.
    #load_balancers:
    #  my_lb_name:
    #    listeners:
    #      - protocol: http
    #        port: 80
    #        instance_port: 8080
    #      - protocol: tcp
    #        port: 443
    #        instance_port: 8080
    #    target_roles: [app]
    #
    #isolate_load_balancers: true



    # get remote lbs
    # for each local not in remote, add it
    #   get all zones for all instances for roles, and make sure in lb
    #   warn if lb not balanced (count of instances per zone is equal)
    # for each local that is in remote, sync listeners and zones
    # for each remote not in local, remove it
  end

end
