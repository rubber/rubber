module Rubber
  module Core
    class Configuration
      def aliases
        return @aliases if defined? @aliases

        instance_aliases = get_env('ALIAS', "Instance alias (e.g. web01 or web01~web05,web09)", true)

        @aliases = Rubber::Util::parse_aliases(instance_aliases)
      end

      def roles
        return @roles if defined? @roles

        if aliases.size > 1
          default_roles = "roles for instance in *.yml"
          roles_string = get_env("ROLES", "Instance roles (e.g. web,app,db:primary=true)", false, default_roles)
          roles_string = "" if roles_string == default_roles
        else
          env = rubber_cfg.environment.bind(nil, aliases.first)
          default_roles = env.instance_roles
          roles_string = get_env("ROLES", "Instance roles (e.g. web,app,db:primary=true)", true, default_roles)
        end

        if roles_string == '*'
          @roles = rubber_cfg.environment.known_roles.reject {|r| r =~ /slave/ || r =~ /^db$/ }
        else
          @roles = roles_string.split(/\s*,\s*/)
        end

        @roles
      end

      def roles_2
        roles_string = get_env('ROLES', "Instance roles (e.g. web,app,db:primary=true)", true)

        # Parse roles_string into an Array of roles
        ir = roles_string.split(/\s*,\s*/).map{ |r| Rubber::Configuration::RoleItem.parse(r) }

        # Add in roles that the given set of roles depends on
        Rubber::Configuration::RoleItem.expand_role_dependencies(ir, get_role_dependencies)
      end

      def spot_instance?
        return @spot_instance if defined? @spot_instance

        @spot_instance = ENV.delete("SPOT_INSTANCE")
      end

      def force?
        return @force if @force

        @force = !!(ENV['FORCE'] =~ /^(t|y)/)
      end
    end
  end
end
