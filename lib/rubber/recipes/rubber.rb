# add this plugins lib dir to load path for capistrano
$:.unshift "#{File.dirname(__FILE__)}/../lib"
require 'rubygems'
require "socket"
require 'resolv'
require 'enumerator'
require 'capistrano/hostcmd'
require 'capistrano/thread_safety_fix'
require 'capistrano/find_servers_for_task_fix'
require 'pp'
require 'rubber'

namespace :rubber do

  # Disable connecting to any Windows instance.
  alias :original_task :task
  def task(name, options={}, &block)
    if options.has_key?(:only)
      options[:only][:platform] = Rubber::Platforms::LINUX
    else
      options[:only] = { :platform => Rubber::Platforms::LINUX }
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
          options[:only][:platform] = Rubber::Platforms::LINUX
        else
          options[:only] = { :platform => Rubber::Platforms::LINUX }
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

    rubber_cfg.instance.each { |instance| instance.capistrano = self }

    # Disable connecting to any Windows instance.
    # pass -l to bash in :shell to that run also gets full env
    # use a pty so we don't get "stdin: is not a tty" error output
    default_run_options[:pty] = true if default_run_options[:pty].nil?
    default_run_options[:shell] = "/bin/bash -l" if default_run_options[:shell].nil?

    if default_run_options.has_key?(:only)
      default_run_options[:only][:platform] = Rubber::Platforms::LINUX
    else
      default_run_options[:only] = { :platform => Rubber::Platforms::LINUX }
    end

    set :cloud, Rubber.cloud(self)

    load_roles() unless rubber_env.disable_auto_roles
    # NOTE: for some reason Capistrano requires you to have both the public and
    # the private key in the same folder, the public key should have the
    # extension ".pub".

    #ssh keys could be multiple, even from ENV. This is comma separated.
    ssh_keys = if ENV['RUBBER_SSH_KEY']
      ENV['RUBBER_SSH_KEY'].split(',')
    else
      if cloud.env.key_file.nil?
        fatal "Missing required cloud provider configuration item 'key_file'."
      else
        cloud.env.key_file
      end
    end

    normalized_ssh_keys = [ssh_keys].flatten.compact

    # Fail-safe check.  While we do some validation earlier in the cycle, on the off-chance after all
    # that, we still have no configured keys, we need to catch it.
    if normalized_ssh_keys.empty?
      fatal "No configured SSH keys. Please set the 'key_file' parameter for your cloud provider."
    end

    # Check that the configuration not only exists, but is also valid.
    normalized_ssh_keys.each do |key|
      unless File.exists?(File.expand_path(key))
        fatal "Invalid SSH key path '#{key}': File does not exist.\nPlease check your cloud provider's 'key_file' setting for correctness."
      end
    end

    ssh_options[:keys] = normalized_ssh_keys
    ssh_options[:timeout] = fetch(:ssh_timeout, 5)

    # If we don't explicitly set :auth_methods to nil, they'll be populated with net-ssh's defaults, which don't
    # work terribly well with Capistrano.  If we set it to nil, Capistrano will use its own defaults.  Moreover,
    # Capistrano seems to have a bug whereby it will not allow password-based authentication unless its default
    # auth_methods are used, so we're best off using that unless the methods have already been set explicitly by
    # the Rubber user elsewhere.
    ssh_options[:auth_methods] = nil unless ssh_options.has_key?(:auth_methods)

    # Starting with net-ssh 2.9.2, net-ssh will block on a password prompt if a nil password is supplied.  This
    # breaks our discovery and retry logic.  To return to the old behavior, we can set set the number of password
    # prompts to 0.  We handle password prompts directly ourselves, using Capistrano's helpers, so this is a
    # safe thing to do.
    ssh_options[:number_of_password_prompts] = 0
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

def top.rubber_instance
  hostname = capture('hostname').chomp

  rubber_instances[hostname]
end

Dir[File.join(File.dirname(__FILE__), 'rubber/*.rb')].each do |rubber_part|
  load(rubber_part)
end
