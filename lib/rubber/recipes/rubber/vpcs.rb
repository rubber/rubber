require 'rubber/environment'

namespace :rubber do
  desc <<-DESC
    Sets up the VPC identified by vpc_alias
  DESC
  required_task :create_vpc do
    vpc_alias = get_env("ALIAS", "VPC Alias: ", true, Rubber.config.cloud_providers['aws'].vpc_alias)
    vpc_cidr = get_env("CIDR", "CIDR Block (eg: 10.0.0.0/16): ", true, Rubber.config.cloud_providers['aws'].vpc_cidr)

    cloud.setup_vpc(vpc_alias, vpc_cidr)
  end

  desc <<-DESC
    List all VPCs (not just Rubber-created)
  DESC
  required_task :describe_vpcs do
    vpcs = cloud.describe_vpcs

    if vpcs
      puts "VPCs:"
      puts "\t\tId\tName\t\t\tRubber Alias"

      vpcs.each do |vpc|
        puts "\t#{vpc[:id]}\t#{vpc[:name]}\t#{vpc[:rubber_alias]}"
      end
    else
      puts "No VPCs found"
    end
  end

  desc <<-DESC
    Configure a new subnet on the configured VPC
  DESC
  required_task :create_vpc_subnet do
    vpc_alias = get_env("ALIAS", "VPC Alias: ", true, Rubber.config.cloud_providers['aws'].vpc_alias)
    cidr = get_env("CIDR", "CIDR Block (eg: 10.0.0.0/24): ", true)
    gateway = get_env("GATEWAY", "Gateway (\"public\" or NAT instance alias): ", true)
    zone = get_env("ZONE", "Availability Zone: ", true, Rubber.config.cloud_providers['aws'].availability_zone)
    name = get_env("NAME", "Subnet name: ", true)

    vpc_id = cloud.compute_provider.vpcs.all('tag:RubberVpcAlias' => vpc_alias).first.id

    unless gateway == 'public'
      gateway = Rubber.config.rubber_instances.find { |i|
        i.name == gateway
      }.instance_id
    end

    private_nic = {
      subnet_cidr: subnet_cidr,
      gateway: gateway
    }

    cloud.setup_vpc_subnet(vpc_id, vpc_alias, private_nic, zone, name)
  end

  desc <<-DESC
    Destroy any VPC with a Rubber-defined Alias
  DESC
  required_task :destroy_vpc do
    vpc_alias = get_env("ALIAS", "VPC Alias: ", true, Rubber.config.cloud_providers['aws'].vpc_alias)
    value = Capistrano::CLI.ui.ask("Are you sure you want to destroy vpc #{vpc_alias} [yes/NO]?: ")

    if value == 'yes'
      cloud.destroy_vpc(vpc_alias)
    else
      fatal "aborted", 0
    end
  end

  desc <<-DESC
    Refresh the public gateway on a public subnet, or configure a new NAT instance on a private subnet.
    This currently does not support switching a public subnet to private or vice versa.
  DESC
  required_task :update_vpc_gateway do
    vpc_alias = get_env("ALIAS", "VPC Alias: ", true, Rubber.config.cloud_providers['aws'].vpc_alias)
    zone = get_env("ZONE", "Availability Zone: ", true, Rubber.config.cloud_providers['aws'].availability_zone)
    gateway = get_env("GATEWAY", "Gateway (\"public\" or NAT instance alias): ", true)

    unless gateway == 'public'
      gateway = Rubber.config.rubber_instances.find { |i|
        i.name == gateway
      }.instance_id
    end

    cloud.update_vpc_gateway(vpc_alias, zone, gateway)
  end
end

