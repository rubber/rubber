namespace :rubber do

  desc "Back up and register an image of the running instance"
  task :bundle do
    if find_servers_for_task(current_task).size > 1
      fatal "Can only bundle a single instance at a time, use FILTER to limit the scope"
    end
    image_name = get_env('IMAGE', "The image name for the bundle", true, Time.now.strftime("%Y%m%d_%H%M"))
    image_id = cloud.create_image(image_name)
    logger.info "Newly registered image is: #{image_id}"
  end

  desc "De-register and Destroy the image for the given name"
  required_task :destroy_bundle do
    image_id = get_env('IMAGE_ID', 'The id of the image to be destroyed', true)
    cloud.destroy_image(image_id)
  end

  desc "Describes all your own image bundles"
  required_task :describe_bundles do
    images = cloud.describe_images()
    images.each do |image|
      logger.info "======================"
      logger.info "ID: #{image[:id]}"
      logger.info "Location: #{image[:location]}"
      logger.info "Root device type: #{image[:root_device_type]}"
    end
  end

end