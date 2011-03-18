# add this plugins lib dir to load path for capistrano
$:.unshift "#{File.dirname(__FILE__)}/../lib"
require 'rubygems'
require "socket"
require 'resolv'
require 'enumerator'
require 'capistrano/hostcmd'
require 'pp'
require 'rubber'

namespace :rubber do

  # Disable connecting to any Windows instance.
  alias :original_task :task
  def task(name, options={}, &block)
    original_task(name, options.merge(:except => { :platform => 'windows' }), &block)
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
        # Disable connecting to any Windows instance.
        required_task(name, options.merge(:except => { :platform => 'windows' })) do
          # define empty roles for the case when a task has a role that we don't define anywhere
          [*options[:roles]].each do |r|
            roles[r] ||= []
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
    set :rubber_cfg, Rubber::Configuration.get_configuration(RUBBER_ENV)
    set :rubber_env, rubber_cfg.environment.bind()
    set :rubber_instances, rubber_cfg.instance

    # Disable connecting to any Windows instance.
    # pass -l to bash in :shell to that run also gets full env
    # use a pty so we don't get "stdin: is not a tty" error output
    default_run_options[:pty] = true
    default_run_options[:shell] = "/bin/bash -l"
    default_run_options[:except] = { :platform => 'windows' }

    # sharing a Net::HTTP instance across threads doesn't work, so create a new instance per thread
    set :cloud, Rubber::ThreadSafeProxy.new { Rubber::Cloud::get_provider(rubber_env.cloud_provider || "aws", rubber_env, self) }

    load_roles() unless rubber_env.disable_auto_roles
    # NOTE: for some reason Capistrano requires you to have both the public and
    # the private key in the same folder, the public key should have the
    # extension ".pub".
    ssh_options[:keys] = rubber_env.cloud_providers[rubber_env.cloud_provider].key_file
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
        opts = Rubber::Util::symbolize_keys(role.options).merge(:platform => ic.platform)
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
