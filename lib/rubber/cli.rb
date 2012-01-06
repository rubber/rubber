require "thor"
require "thor/group"
require "thor/runner"

# monkey patch thor arg parsing to allow "--" to short circuit
# parsing - standard in most cli parsing systems
class Thor::Arguments
  private
  def peek
    p = @pile.first
    p == "--" ? nil : p
  end
end

module Rubber

  class CLI < Thor
    
    # Override Thor#help so it can give information about any class and any method.
    #
    def help(meth = nil)
      initialize_thorfiles
      if meth && !self.respond_to?(meth)
        klass, task = find_class_and_task_by_namespace(meth)
        klass.start(["-h", task].compact, :shell => self.shell)
      else
        display_klasses
      end
    end

    # If a task is not found on Thor::Runner, method missing is invoked and
    # Thor::Runner is then responsable for finding the task in all classes.
    #
    def method_missing(meth, *args)
      initialize_thorfiles

      klass, task = find_class_and_task_by_namespace(meth)

      args.unshift(task) if task
      klass.start(args, :shell => self.shell)
    end

    private

    def find_class_and_task_by_namespace(meth)
      meth = meth.to_s

      pieces = meth.split(":")
      task   = pieces.pop
      namespace = pieces.join(":")
      namespace = "default#{namespace}" if namespace.empty? || namespace =~ /^:/

      klass = Thor::Base.subclasses.find { |k| k.namespace == namespace && k.tasks[task] }
      return klass, task
    end

    def self.exit_on_failure?
      true
    end

    def initialize_thorfiles
      files = Dir[File.expand_path(File.join(File.dirname(__FILE__), 'commands/*.rb'))]
      files.each do |f|
        require f
      end
    end

    def display_klasses(show_internal=false, klasses=Thor::Base.subclasses)
      klasses -= [Thor, Thor::Runner, Thor::Group] unless show_internal

      raise Error, "No Thor tasks available" if klasses.empty?

      list = Hash.new { |h,k| h[k] = [] }
      groups = klasses.select { |k| k.ancestors.include?(Thor::Group) }

      # Get classes which inherit from Thor
      (klasses - groups).each { |k| list[k.namespace.split(":").first] += k.printable_tasks(false) }

      # Get classes which inherit from Thor::Base
      groups.map! { |k| k.printable_tasks(false).first }
      list["root"] = groups

      # Order namespaces with default coming first
      list = list.sort{ |a,b| a[0].sub(/^default/, '') <=> b[0].sub(/^default/, '') }
      list.each { |n, tasks| display_tasks(n, tasks) unless tasks.empty? }
    end

    def display_tasks(namespace, list) #:nodoc:
      list.sort!{ |a,b| a[0] <=> b[0] }

      say shell.set_color(namespace, :blue, true)
      say "-" * namespace.size

      print_table(list, :truncate => true)
      say
    end

  end
  
end
