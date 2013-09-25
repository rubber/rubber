namespace :rubber do

  namespace :discourse do

    after "rubber:postgresql:bootstrap", "rubber:discourse:create_postgres_extensions"

    task :create_postgres_extensions, :roles => :postgresql_master do
      rsudo "export DEBIAN_FRONTEND=noninteractive; apt-get -q -o Dpkg::Options::=--force-confold -y --force-yes install postgresql-contrib"
      rubber.sudo_script "create_extensions", <<-ENDSCRIPT
        sudo -i -u postgres psql -c "CREATE EXTENSION IF NOT EXISTS hstore;" -d "#{rubber_env.db_name}"
        sudo -i -u postgres psql -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;" -d "#{rubber_env.db_name}"
      ENDSCRIPT
    end
  end

end