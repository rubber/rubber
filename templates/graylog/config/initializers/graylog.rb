require 'gelf'

graylog_server = Rubber.instances.for_role('graylog_server').first

if graylog_server

  class MultiLogger
    def initialize(*objects)
      @objects = objects
    end

    def method_missing(*args)
      @objects.each {|o| o.send(*args) }
    end
  end
  
  gelf_logger = GELF::Logger.new(graylog_server.full_name,
                                 Rubber.config.graylog_server_port,
                                 'LAN',
                                 'facility' => 'rails',
                                 'host' => Rubber.config.host)
  Rails.logger = MultiLogger.new(Rails.logger, gelf_logger)

  # See https://github.com/Graylog2/graylog2_exceptions/wiki
  Rails.application.config.middleware.use "Graylog2Exceptions",
                                          {
                                            :hostname => graylog_server.full_name,
                                            :port => Rubber.config.graylog_server_port,
                                            :facility => "rails_exceptions",
                                            :local_app_name => Rubber.config.host,
                                            :level => GELF::FATAL,
                                            :max_chunk_size => 'LAN'
                                          }

  # Setup logging unhandled resque exceptions to graylog
  Graylog2::Resque::FailureHandler.configure do |config|
    config.gelf_server = graylog_server.full_name
    config.gelf_port = Rubber.config.graylog_server_port
    config.host = Rubber.config.host
    config.facility = "resque_exceptions"
    config.level = GELF::FATAL
    config.max_chunk_size = 'LAN'
  end
 
  require 'resque/failure/multiple'
  require 'resque/failure/redis'
  Resque::Failure::Multiple.classes = [
      Graylog2::Resque::FailureHandler,
      Resque::Failure::Redis
  ]
  Resque::Failure.backend = Resque::Failure::Multiple

end
