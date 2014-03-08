namespace :rubber do
  namespace :elasticache do

    desc <<-DESC
      Create an ElastiCache cluster
    DESC
    task :create do
      creation_threads = []
      refresh_threads = []

      name      = get_env('ALIAS', "Cluster alias (e.g. cache01)", true)
      node_type = get_env('NODE_TYPE', "Node Type", false, "cache.m1.large")
      engine    = get_env('ENGINE', "Engine, memcached or redis", false, "memcached")

      artifacts = rubber_instances.artifacts

      cluster_item = Rubber::Configuration::ClusterItem.new(name, node_type, engine)
      artifacts['clusters'][name] = cluster_item

      logger.info "Allocating Cache Cluster"

      creation_threads << Thread.new do
        create_cache_cluster(name, node_type, engine)

        refresh_threads << Thread.new do
          while ! refresh_cluster(name)
            sleep 1
          end
        end
      end

      creation_threads.each {|t| t.join }

      print "Waiting for cluster to start up. This may take a minute"

      while true do
        print "."
        sleep 2

        break if refresh_threads.all? {|t| ! t.alive? }
      end

      refresh_threads.each {|t| t.join }

      save_nodes(name)
    end

    def refresh_cluster(name)
      cluster = elastic.clusters.detect {|c| c.id == name }
      if cluster.status == "available"
        return true
      end
      false
    end

    def save_nodes(name)
      cluster = elastic.clusters.detect {|c| c.id == name }
      node = cluster.nodes.first
      node = Rubber::Configuration::ClusterNodeItem.new(node["CacheNodeId"], node["Address"], node["Port"])

      artifacts = rubber_instances.artifacts
      artifacts["clusters"][name].nodes = [node]
      rubber_instances.save
    end

    desc <<-DESC
      Destroy an ElastiCache cluster
    DESC
    task :destroy do
      name = get_env('ALIAS', "Cluster alias (e.g. cache01)", true)
      logger.info "Destroying Cache Cluster"
      destroy_cache_cluster(name)
      rubber_instances.artifacts["clusters"].delete(name)
      rubber_instances.save
    end

    desc <<-DESC
      Describe all ElastiCache clusters
    DESC
    task :describe do
      results = []
      format = "%-10s %-15s %-10s %-10s %-15s"
      results << format % %w[Name Type State Engine Security Groups]

      clusters = elastic.clusters
      data = []
      clusters.each do |c|
        data << [c.id, c.node_type, c.status, c.engine, c.security_groups]
      end

      # sort by name
      data = data.sort {|r1, r2| r1.last <=> r2.last }
      results.concat(data.collect {|r| format % r})
      results.each {|r| logger.info(r) }
    end

    def create_cache_cluster(name, type, engine)
      cluster = elastic.clusters.new(id: name,
                           node_type: type,
                           engine: engine,
                           security_groups: [cache_cluster_security_group])

      cluster.save
    end

    def destroy_cache_cluster(name)
      cluster = elastic.clusters.select {|c| c.id == name }.first
      cluster.destroy
    end

    # Create it for the rubber environment
    # match it to the default ec2 security group
    def cache_cluster_security_group
      group = if cache_security_group
        cache_security_group
      else
        group = create_default_security_group
        authorize_default_ec2_for(group)
      end

      group.id
    end

    def create_default_security_group
      group = elastic.security_groups.new(
          id: Rubber.env,
          description: "Automatically created by rubber"
        )
      group.save
      group.reload
    end

    def authorize_default_ec2_for(group)
      default_group_name = [rubber_env.app_name, rubber_env.env, "default"].join("_")
      opts = {}
      opts["group-name"] = default_group_name
      default_ec2_security_group = cloud.compute_provider.security_groups.all(opts).first

      group.authorize_ec2_group(default_group_name, default_ec2_security_group.owner_id)
      group
    end

    def cache_security_group
      elastic.security_groups.select {|s| s.id == Rubber.env }.first
    end

    def elastic
      @elastic ||= ::Fog::AWS::Elasticache.new
    end

  end
end