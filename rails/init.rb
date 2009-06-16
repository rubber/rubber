# this file just makes it easy to refer to rubber config
# variables in your apps's config'
#

require "rubber"
Rubber::initialize(RAILS_ROOT, RAILS_ENV)

::RUBBER_CONFIG = Rubber::Configuration.rubber_env
::RUBBER_INSTANCES = Rubber::Configuration.rubber_instances
