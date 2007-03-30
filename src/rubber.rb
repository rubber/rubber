#
# Copyright (c) 2007 Martin Simbartl
# This file is distributed under the terms of MIT license. See LICENSE file for more information.
#
# Description:
#   Entry point of Rubber application.
# Version:
#   $Id$
#
module Rubber
	VERSION = '0.0.0.0'
end

if __FILE__ == $0
	puts "Rubber, version #{Rubber::VERSION}"
	puts 'Hello World! :)'
end
