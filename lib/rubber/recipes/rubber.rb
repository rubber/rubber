# add this plugins lib dir to load path for capistrano
$:.unshift "#{File.dirname(__FILE__)}/../lib"
require 'rubygems'
require "socket"
require 'resolv'
require 'enumerator'
require 'capistrano/hostcmd'
require 'capistrano/thread_safety_fix'
require 'pp'
require 'rubber'

namespace :rubber do

  # Disable connecting to any Windows instance.
  alias :original_task :task
  def task(name, options={}, &block)
    if options.has_key?(:only)
      options[:only][:platform] = 'linux'
    else
      options[:only] = { :platform => 'linux' }
    end

    original_task(name, options, &block)
  end

  # advise capistrano's task method so that tasks for non-existent roles don't
  # fail when roles isn't defined due to using a FILTER for load_roles
  # If you have a task you need to execute even when there are no
  # roles, you have to use required_task instead of task - see rubber:create
  # as an example of this role bootstrapping problem.
  def allow_optional_tasks(ns)
    class << ns
      alias :required_task :task
      def task(name, options={}, &block)
        if options.has_key?(:only)
          options[:only][:platform] = 'linux'
        else
          options[:only] = { :platform => 'linux' }
        end

        required_task(name, options) do
          # define empty roles for the case when a task has a role that we don't define anywhere
          unless options[:roles].respond_to?(:call)
            [*options[:roles]].each do |r|
              top.roles[r] ||= []
            end
          end
          
          if find_servers_for_task(current_task).empty?
            logger.info "No servers for task #{name}, skipping"
            next
          end
          block.call
        end
      end
    end
  end

  allow_optional_tasks(self)
  on :load, "rubber:init"
    
  required_task :init do
    set :rubber_cfg, Rubber::Configuration.get_configuration(Rubber.env)
    set :rubber_env, rubber_cfg.environment.bind()
    set :rubber_instances, rubber_cfg.instance

    # Disable connecting to any Windows instance.
    # pass -l to bash in :shell to that run also gets full env
    # use a pty so we don't get "stdin: is not a tty" error output
    default_run_options[:pty] = true if default_run_options[:pty].nil?
    default_run_options[:shell] = "/bin/bash -l" if default_run_options[:shell].nil?

    if default_run_options.has_key?(:only)
      default_run_options[:only][:platform] = 'linux'
    else
      default_run_options[:only] = { :platform => 'linux' }
    end

    set :cloud, Rubber.cloud(self)

    load_roles() unless rubber_env.disable_auto_roles
    # NOTE: for some reason Capistrano requires you to have both the public and
    # the private key in the same folder, the public key should have the
    # extension ".pub".

    ssh_options[:keys] = [ENV['RUBBER_SSH_KEY'] || cloud.env.key_file].flatten.compact
    ssh_options[:timeout] = fetch(:ssh_timeout, 5)
  end


  # Automatically load and define capistrano roles from instance config
  def load_roles
    top.roles.clear

    # define empty roles for all known ones so tasks don't fail if a role
    # doesn't exist due to a filter
    all_roles = rubber_instances.all_roles
    all_roles += rubber_cfg.environment.known_roles
    all_roles.uniq!
    all_roles.each {|name| top.roles[name.to_sym] = []}

    # define capistrano host => role mapping for all instances
    rubber_instances.filtered.each do |ic|
      ic.roles.each do |role|
        opts = Rubber::Util::symbolize_keys(role.options).merge(:platform => ic.platform, :provider => ic.provider)
        msg = "Auto role: #{role.name.to_sym} => #{ic.full_name}"
        msg << ", #{opts.inspect}" if opts.inspect.size > 0
        logger.info msg
        top.role role.name.to_sym, ic.full_name, opts
      end
    end
  end

end

Dir[File.join(File.dirname(__FILE__), 'rubber/*.rb')].each do |rubber_part|
  load(rubber_part)
end
