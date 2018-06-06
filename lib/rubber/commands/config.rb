
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
        server_alias = host || cfg.environment.current_host
        server = cfg.cluster[server_alias]
        if server
          role_names = server.role_names
          env = cfg.environment.bind(role_names, server_alias)
          gen = Rubber::Configuration::Generator.new("#{Rubber.root}/config/rubber", role_names, server_alias)
          gen.fake_root = fakeroot if fakeroot
        elsif ['development', 'test'].include?(Rubber.env)
          server_alias = host || server_alias
          role_names = roles || cfg.environment.known_roles
          role_items = role_names.collect do |r|
            Rubber::Configuration::RoleItem.new(r, r == "db" ? {'primary' => true} : {})
          end
          env = cfg.environment.bind(role_names, server_alias)
          domain = env.domain
          server = Rubber::Configuration::ServerItem.new(server_alias, domain, role_items,
                                                             'dummyid', 'm1.small', 'ami-7000f019', ['dummygroup'])
          server.external_host = server.full_name
          server.external_ip = "127.0.0.1"
          server.internal_host = server.full_name
          server.internal_ip = "127.0.0.1"
          cfg.server.add(server)
          gen = Rubber::Configuration::Generator.new("#{Rubber.root}/config/rubber", role_names, server_alias)
          gen.fake_root = fakeroot || "#{Rubber.root}/tmp/rubber"
        else
          puts "Server not found for host: #{server_alias}"
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
