
module Rubber
  module Commands

    class Config < Thor

      namespace :default

      method_option :host, :type => :string, :aliases => "-h",
                           :desc => "Override the instance's host for generation"
      method_option :roles, :type => :string, :aliases => "-r",
                           :desc => "Override the instance's roles for generation"
      method_option :file, :type => :string, :aliases => "-p",
                           :desc => "Only generate files that match the given pattern"
      method_option :no_post, :type => :boolean, :aliases => "-n",
                           :desc => "Skip running post commands for files that get generated"
      method_option :force, :type => :boolean, :aliases => "-f",
                           :desc => "Overwrite files that already exist"

      desc "config", Rubber::Util.clean_indent(<<-EOS
        Generate system config files by transforming the files in the config/rubber tree
      EOS
      )

      def config
        cfg = Rubber::Configuration.get_configuration(Rubber.env)
        instance_alias = cfg.environment.current_host
        instance = cfg.instance[instance_alias]
        if instance
          roles = instance.role_names
          env = cfg.environment.bind(roles, instance_alias)
          gen = Rubber::Configuration::Generator.new("#{Rubber.root}/config/rubber", roles, instance_alias)
        elsif ['development', 'test'].include?(Rubber.env)
          instance_alias = options[:host] || instance_alias
          roles = options[:roles].split(',') if options[:roles]
          roles ||= cfg.environment.known_roles
          role_items = roles.collect do |r|
            Rubber::Configuration::RoleItem.new(r, r == "db" ? {'primary' => true} : {})
          end
          env = cfg.environment.bind(roles, instance_alias)
          domain = env.domain
          instance = Rubber::Configuration::InstanceItem.new(instance_alias, domain, role_items,
                                                             'dummyid', 'm1.small', 'ami-7000f019', ['dummygroup'])
          instance.external_host = instance.full_name
          instance.external_ip = "127.0.0.1"
          instance.internal_host = instance.full_name
          instance.internal_ip = "127.0.0.1"
          cfg.instance.add(instance)
          gen = Rubber::Configuration::Generator.new("#{Rubber.root}/config/rubber", roles, instance_alias)
          gen.fake_root ="#{Rubber.root}/tmp/rubber"
        else
          puts "Instance not found for host: #{instance_alias}"
          exit 1
        end
        
        if options[:file]
          gen.file_pattern = options[:file]
        end
        gen.no_post = options[:no_post]
        gen.force = options[:force]
        gen.stop_on_error_cmd = env.stop_on_error_cmd
        gen.run

      end

    end

  end
end
