require 'capistrano/recipes/deploy/scm/base'
require 'yaml'

module Capistrano
  module Deploy
    module SCM
      class <<self
        alias cap_new new
      end
      def self.new(scm, config={})
        return Noscm.new(config) if scm == :noscm
        self.cap_new(scm, config)
      end

      # Implements the Capistrano SCM interface for the a plain directory tree
      class Noscm < Base
        # Sets the default command name for this SCM. Users may override this
        # by setting the :scm_command variable.
        default_command "cp -R"

        def head
          "1"
        end

        def query_revision(revision)
          return "1"
        end

        # Returns the command that will do an "svn export" of the given revision
        # to the given destination.
        def export(revision, destination)
          "#{default_command} . #{destination}"
        end

      end

    end
  end
end
