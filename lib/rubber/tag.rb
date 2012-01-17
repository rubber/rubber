module Rubber
  module Tag
    # Updates the tags for the given ec2 instance
    def self.update_instance_tags(instance_alias)
      instance_item = Rubber.instances[instance_alias]
      raise "Instance does not exist: #{instance_alias}" if ! instance_item

      Rubber.cloud.create_tags(instance_item.instance_id, :Name => instance_alias, :Environment => Rubber.env)
    end
  end
end