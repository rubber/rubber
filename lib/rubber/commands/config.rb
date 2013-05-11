
module Rubber
  module Commands

    class Config < Clamp::Command

      def self.subcommand_name
        "config"
      end

      def self.subcommand_description
        "Transform templates in the config/rubber tree"
      end
      
      def self.description
        "Generate system files by transforming the files in the config/rubber tree"
      end
      
      option ["--host", "-h"], "HOST", "Override the instance's host for generation"
      option ["--roles", "-r"], "ROLES", "Override the instance's roles for generation" do |str|
        str.split(/\s*,\s*/)
      end
      option ["--file", "-p"], "FILE", "Only generate files matching the given pattern"
      option ["--no_post", "-n"], :flag, "Skip running post commands"
      option ["--force", "-f"], :flag, "Overwrite files that already exist"
      option ["--fakeroot", "-k"], "FAKEROOT", "Prefix generated files with fakeroot. Useful\nfor debugging with an environment and host"
      
      def execute
        cfg = Rubber::Configuration.get_configuration(Rubber.env)
        instance_alias = host || cfg.environment.current_host 
        instance = cfg.instance[instance_alias]
        if instance
          role_names = instance.role_names
          env = cfg.environment.bind(role_names, instance_alias)
          gen = Rubber::Configuration::Generator.new("#{Rubber.root}/config/rubber", role_names, instance_alias)
          gen.fake_root = fakeroot if fakeroot
        elsif ['development', 'test'].include?(Rubber.env)
          instance_alias = host || instance_alias
          role_names = roles || cfg.environment.known_roles
          role_items = role_names.collect do |r|
            Rubber::Configuration::RoleItem.new(r, r == "db" ? {'primary' => true} : {})
          end
          env = cfg.environment.bind(role_names, instance_alias)
          domain = env.domain
          instance = Rubber::Configuration::InstanceItem.new(instance_alias, domain, role_items,
                                                             'dummyid', 'm1.small', 'ami-7000f019', ['dummygroup'])
          instance.external_host = instance.full_name
          instance.external_ip = "127.0.0.1"
          instance.internal_host = instance.full_name
          instance.internal_ip = "127.0.0.1"
          cfg.instance.add(instance)
          gen = Rubber::Configuration::Generator.new("#{Rubber.root}/config/rubber", role_names, instance_alias)
          gen.fake_root = fakeroot || "#{Rubber.root}/tmp/rubber"
        else
          puts "Instance not found for host: #{instance_alias}"
          exit 1
        end
        
        if file
          gen.file_pattern = file
        end
        gen.no_post = no_post?
        gen.force = force?
        gen.stop_on_error_cmd = env.stop_on_error_cmd
        gen.run

      end

    end

  end
end
