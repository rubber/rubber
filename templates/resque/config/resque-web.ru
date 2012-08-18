# This file is used by Rack-based servers to start resque web
# we load environment to get the rails environment, because plugins
# like resque-retry reference job classes from one's environment within
# the web ui
require ::File.expand_path('../environment',  __FILE__)
run Resque::Server
