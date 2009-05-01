namespace :rubber do

  set :mnt_vol, "/mnt"

  desc "Back up and register an image of the running instance to S3"
  task :bundle do
    if find_servers_for_task(current_task).size > 1
      fatal "Can only bundle a single instance at a time, use FILTER to limit the scope"
    end
    image_name = get_env('IMAGE', "The image name for the bundle", true, Time.now.strftime("%Y%m%d_%H%M"))
    bundle_vol(image_name)
    upload_bundle(image_name)
  end

  desc "De-register and Destroy the bundle for the given image name"
  required_task :destroy_bundle do
    ami = get_env('AMI', 'The AMI id of the image to be destroyed', true)
    delete_bundle(ami)
  end

  desc "Describes all your own registered bundles"
  required_task :describe_bundles do
    describe_bundles
  end

  def bundle_vol(image_name)
    env = rubber_cfg.environment.bind()
    ec2_key = env.ec2_key_file
    ec2_pk = env.ec2_pk_file
    ec2_cert = env.ec2_cert_file
    aws_account = env.aws_account
    ec2_key_dest = "#{mnt_vol}/#{File.basename(ec2_key)}"
    ec2_pk_dest = "#{mnt_vol}/#{File.basename(ec2_pk)}"
    ec2_cert_dest = "#{mnt_vol}/#{File.basename(ec2_cert)}"

    put(File.read(ec2_key), ec2_key_dest)
    put(File.read(ec2_pk), ec2_pk_dest)
    put(File.read(ec2_cert), ec2_cert_dest)

    arch = capture "uname -m"
    arch = case arch when /i\d86/ then "i386" else arch end
    sudo_script "create_bundle", <<-CMD
      export RUBYLIB=/usr/lib/site_ruby/
      ec2-bundle-vol --batch -d #{mnt_vol} -k #{ec2_pk_dest} -c #{ec2_cert_dest} -u #{aws_account} -p #{image_name} -r #{arch}
    CMD
  end

  def upload_bundle(image_name)
    env = rubber_cfg.environment.bind()

    sudo_script "register_bundle", <<-CMD
      export RUBYLIB=/usr/lib/site_ruby/
      ec2-upload-bundle --batch -b #{env.ec2_image_bucket} -m #{mnt_vol}/#{image_name}.manifest.xml -a #{env.aws_access_key} -s #{env.aws_secret_access_key}
    CMD

    image_id = cloud.register_image("#{env.ec2_image_bucket}/#{image_name}.manifest.xml")
    logger.info "Newly registered AMI is: #{image_id}"
  end

  def describe_bundles
    images = cloud.describe_images()
    images.each do |image|
      logger.info "AMI: #{image[:id]}"
      logger.info "Location: #{image[:location]}"
    end
  end

  def delete_bundle(ami)
    cloud.destroy_image(ami)
  end

end