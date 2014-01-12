module Rubber
  module Platforms
    LINUX = 'linux'.freeze
    WINDOWS = 'windows'.freeze
    MAC = 'mac'.freeze

    ALL = [LINUX, WINDOWS, MAC]
    NON_LINUX = ALL# - [LINUX]
  end
end