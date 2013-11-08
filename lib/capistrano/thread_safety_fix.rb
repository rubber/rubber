require 'capistrano/configuration'

# Overrides a method in Capistrano::Configurations::Connections that has multiple threads writing to a shared hash.
# While that shared hash is a thread local variable, they the thread is passed as an argument, so all the connection
# threads are trying to update it at the same time.  This has been observed to cause problems where servers will end
# up losing their connection objects, messing up all future SSH operations and eventually leading to an error about
# calling a method on a nil object.
#
# We shouldn't make a habit of patching Capistrano in Rubber. But since Capistrano 2.x is effectively a dead project,
# getting this fixed upstream is extremely unlikely.

module Capistrano
  class Configuration
    private

    MUTEX = Mutex.new

    def safely_establish_connection_to(server, thread, failures=nil)
      conn = connection_factory.connect_to(server)

      MUTEX.synchronize do
        thread[:sessions] ||= {}
        thread[:sessions][server] ||= conn
      end
    rescue Exception => err
      raise unless failures
      failures << { :server => server, :error => err }
    end
  end
end