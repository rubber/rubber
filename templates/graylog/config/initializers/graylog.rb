require 'gelf'

graylog_server = Rubber.instances.for_role('graylog_server').first

if graylog_server

  Rails.logger = GELF::Logger.new(graylog_server.full_name,
                                  Rubber.config.graylog_server_port,
                                  'LAN',
                                  'facility' => 'rails')

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
  
end
