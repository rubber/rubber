#
# Copyright (c) 2007 Martin Simbartl
# This file is distributed under the terms of MIT license. See LICENSE file for more information.
#
# Description:
#   Entry point of Rubber application.
# Version:
#   $Id$
#
## TODO [mikey] checkout settings of svn keywords replacement
#
module Rubber
  VERSION = '0.0.0.0'
end

if __FILE__ == $0
  require 'xmpp4r/client'
  include Jabber

  puts "Rubber, version #{Rubber::VERSION}"

  raise 'Oops. Give me more args!' if ARGV.size < 3

  login = ARGV[0]
  password = ARGV[1]
  to = ARGV[2]

  jid = JID::new("#{login}/Rubber")
  cl = Client::new(jid)
  puts "connecting to #{login} ..."
  cl.connect
  puts 'authenticating ...'
  cl.auth(password)

  # send presence status: online
  cl.send(Presence.new(nil, nil, 10))

  m = Message::new(to, 'This is a testing message from Rubber, the Jabber client!').set_type(:chat).set_id('1')
  puts "sending testing message to #{to} ..."
  puts m.to_s
  cl.send(m)

  puts 'disconnecting ...'
  cl.close
end
