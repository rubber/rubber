
# rm -rf rubbertest; rails new rubbertest -d postgresql -m rubber/test/test-rails-template.rb
# RUBBER_ENV=production bundle exec cap rubber:create_staging

run "mkdir -p vendor/gems"
run "ln -sf `pwd`/../rubber vendor/gems/rubber"

default_template = "complete_passenger_postgresql"
templates = ask("Which rubber templates [#{default_template}] ?")
templates = default_template if templates.blank?

run "ruby -I vendor/gems/rubber/lib vendor/gems/rubber/bin/rubber vulcanize #{templates}"

gsub_file 'Gemfile', /gem ["']rubber["'].*/, "gem 'rubber', :path => 'vendor/gems/rubber'"
gem 'therubyracer', :group => :assets

run "bundle install"
generate(:scaffold, "post", "title:string", "body:text")

gsub_file 'config/environment.rb', /^RAILS_GEM_VERSION/, '# RAILS_GEM_VERSION'

copy_with_symlink = <<-EOS
require 'capistrano/recipes/deploy/strategy/copy'
set :deploy_via, :copy
set :copy_compression, :zip
# monkey patch so that zip includes symlinked contents for vendored rubber for testing
module ::Capistrano
  module Deploy
    module Strategy
      class Copy < Base
          # The compression method to use, defaults to :gzip.
          def compression
            Compression.new("zip",     %w(zip -qr), %w(unzip -q))
          end
      end
    end
  end
end
EOS

gsub_file 'config/deploy.rb', /set :deploy_via, :copy/, copy_with_symlink
gsub_file 'config/rubber/rubber.yml', /packages: \[/, "packages: [zip, "

# gsub_file 'config/rubber/rubber.yml', /rubber, /, ''
gsub_file 'config/rubber/rubber.yml', /, \[rubber, [^\]]*\]/, ''
gsub_file 'config/rubber/rubber.yml', /,db:primary=true/, ',db:primary=true,web_tools'
gsub_file 'config/rubber/rubber.yml', /image_type: m1.small/, 'image_type: c1.medium'

default_secret = "~/rubber-secret.yml"
secret = ask("Which rubber secret file [#{default_secret}] ?")
secret = default_secret if secret.blank?
run "cp -f #{secret} config/rubber/rubber-secret.yml"
chmod 'config/rubber/rubber-secret.yml', 0644
gsub_file 'config/rubber/rubber-secret.yml', /dns_provider: .*/, ''

run "vagrant init precise32 http://files.vagrantup.com/precise32.box"
vagrantfile = <<-EOS
  config.vm.define :vagrant do |vagrant|
    vagrant.vm.network :private_network, ip: "192.168.70.10"
    
    vagrant.vm.provider :virtualbox do |vb|
      vb.customize ["modifyvm", :id, "--memory", "2048"]
    end

    vagrant.vm.provision :rubber do |rubber|
      rubber.rubber_env = 'vagrant'

      # Only necessary if you use RVM locally.
      rubber.rvm_ruby_version = 'default'
    end
  end
end
EOS

gsub_file 'Vagrantfile', /^end/, vagrantfile
