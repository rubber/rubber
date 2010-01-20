namespace :rubber do

  desc "Describes all your spot instance requests"
  required_task :describe_spot_instance_requests do
    requests = cloud.describe_spot_instance_requests()
    requests.each do |request|
      logger.info "======================"
      logger.info "ID: #{request[:id]}"
      logger.info "Created at: #{request[:created_at]}"
      logger.info "Max. price: $#{request[:spot_price]}"
      logger.info "State: #{request[:state]}"
      logger.info "Instance type: #{request[:type]}"
      logger.info "AMI: #{request[:image_id]}"
    end
  end

  desc "Cancel the spot instances request for the given id"
  required_task :cancel_spot_instances_request do
    request_id = get_env('SPOT_INSTANCE_REQUEST_ID', 'The id of the spot instances request to cancel', true)
    cloud.destroy_spot_instance_request(request_id)
  end

end