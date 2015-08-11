require 'rubber'

module Kitchen
  module Driver
    class Rubber < Kitchen::Driver::Base

      default_config(:server_hostname) do |driver|
        driver.instance.name
      end

      default_config(:server_image) do |driver|
        driver.server_image
      end

      def create(state)
        super

        FileUtils.mkdir_p(project_directory)

        Dir.chdir(File.dirname(project_directory)) do
          basename = File.basename(project_directory)

          FileUtils.rmtree(basename)
          Dir.mkdir(basename)

          Dir.chdir(basename) do
            system("bundle exec rubber vulcanize base")
            File.write('Vagrantfile', generate_vagrantfile)
            FileUtils.cp(File.join(templates_directory, 'rubber-kitchen-env.yml'), File.join('config', 'rubber', 'rubber-kitchen-env.yml'))
            FileUtils.cp(File.join(templates_directory, 'Gemfile'), 'Gemfile')

            Bundler.with_clean_env do
              system("bundle install")

              if config[:cloud_provider] == 'vagrant'
                system("vagrant up")
              else
                system("cd #{ENV['RUBBER_ROOT']} && bundle exec cap rubber:create")
              end

              # We have to init rubber after the instances are created because the instance files is read once a start-up.
              init_rubber

              state[:hostname] = ::Rubber.instances[config[:server_hostname]].external_ip
              state[:ssh_key] = ::Rubber.cloud.env.key_file

              # Disable SSH compression since it doesn't seem to work quite right and upload speed isn't a paramount concern.
              state[:compression] = false
            end
          end
        end
      end

      def destroy(state)
        FileUtils.mkdir_p(project_directory)

        Dir.chdir(project_directory) do
          puts system("FORCE=true RUBBER_ENV=kitchen bundle exec cap rubber:destroy_all")
        end

        super
      end

      def init_rubber
        # This can't be done in `initialize` because the call to `project_directory` requires state that hasn't
        # yet been established at that point.

        env = ENV['RUBBER_ENV'] ||= 'kitchen'
        root = File.expand_path(ENV['RUBBER_ROOT'] || project_directory)
        ::Rubber::initialize(root, env)
      end

      def templates_directory
        File.join(File.dirname(__FILE__), '..', 'templates')
      end

      def project_directory
        File.join(File.dirname(__FILE__), '..', '..', '..', 'test', 'integration', 'workdir', instance.name)
      end

      def generate_vagrantfile
        ERB.new(File.read(File.join(templates_directory, 'Vagrantfile.erb'))).result(binding)
      end

      def server_image
        case config[:cloud_provider]
          when 'vagrant' then
            case instance.platform.name
              when 'ubuntu-12.04' then 'ubuntu/precise64'
              when 'ubuntu-14.04' then 'ubuntu/trusty64'
              else raise "Rubber's kitchen provider doesn't work with platform: #{instance.platform.name}"
            end
          else
            raise "Rubber's kitchen provider doesn't yet work with cloud provider: #{config[:cloud_provider]}"
        end
      end

    end
  end
end