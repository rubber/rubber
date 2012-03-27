require 'rubber'
require 'rails'

module Rubber

  class Railtie < Rails::Railtie

    initializer "rubber.configure_rails_initialization", :before => :load_config_initializers do
      Rubber::initialize(Rails.root, Rails.env)
    end

  end

end
