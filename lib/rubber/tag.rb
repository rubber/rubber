module Rubber
  module Tag
    # Updates the tags for the given ec2 instance
    def self.update_instance_tags(instance_alias)
      instance_item = Rubber::Configuration.rubber_instances[instance_alias]
      fatal "Instance does not exist: #{instance_alias}" if ! instance_item

      rubber_cfg = Rubber::Configuration.get_configuration(RUBBER_ENV)
      rubber_env = rubber_cfg.environment.bind()

      cloud = Rubber::Cloud::get_provider(rubber_env.cloud_provider || "aws", Rubber::Configuration.rubber_env, self)

      cloud.create_tags(instance_item.instance_id, :Name => instance_alias, :Environment => RUBBER_ENV)
    end
  end
end