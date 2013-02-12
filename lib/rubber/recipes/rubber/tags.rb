require 'rubber/tag'

namespace :rubber do
  desc <<-DESC
    Updates ALL the tags on EC2 instances for the current env
  DESC
  required_task :update_tags do
    rubber_instances.each do |ic|
      logger.info "Updating instance tags for #{ic.name}"
      Rubber::Tag::update_instance_tags(ic.name)
    end
  end
end