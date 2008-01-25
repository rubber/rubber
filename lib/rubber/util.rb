

module Rubber
  module Util

    def self.symbolize_keys(map)
      map.inject({}) do |options, (key, value)|
        options[key.to_sym || key] = value
        options
      end
    end

    # Opens the file for writing by root
    def self.sudo_open(path, perms, &block)
      open("|sudo tee #{path} > /dev/null", perms, &block)
    end

  end
end
