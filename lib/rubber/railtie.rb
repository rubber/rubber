require 'rubber'
require 'rails'

module Rubber

  class Railtie < Rails::Railtie

    config.before_configuration do
      Rubber::initialize(Rails.root, Rails.env)
    end

  end

end
