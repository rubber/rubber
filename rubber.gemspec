# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require 'rubber/version'


Gem::Specification.new do |s|

  s.name = "rubber"
  s.version     = Rubber::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors = ["Matt Conway", "Kevin Menard"]
  s.email       = ["matt@conwaysplace.com", "nirvdrum@gmail.com"]
  s.homepage = "https://github.com/rubber/rubber"
  s.summary = "A capistrano plugin for managing multi-instance deployments to the cloud (ec2)"
  s.description = <<-DESC
    The rubber plugin enables relatively complex multi-instance deployments of RubyOnRails applications to
    Amazon's Elastic Compute Cloud (EC2).  Like capistrano, rubber is role based, so you can define a set
    of configuration files for a role and then assign that role to as many concrete instances as needed. One
    can also assign multiple roles to a single instance. This lets one start out with a single ec2 instance
    (belonging to all roles), and add new instances into the mix as needed to scale specific facets of your
    deployment, e.g. adding in instances that serve only as an 'app' role to handle increased app server load.
  DESC

  s.rubyforge_project = 'rubber'

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_dependency 'capistrano', '~> 2.12'
  s.add_dependency 'net-ssh', '~> 2.6'
  s.add_dependency 'thor'
  s.add_dependency 'clamp'
  s.add_dependency 'open4'
  s.add_dependency 'fog', '~> 1.6'
  s.add_dependency 'json'
  
  s.add_development_dependency('rake')
  s.add_development_dependency('test-unit')
  s.add_development_dependency('shoulda-context')
  s.add_development_dependency('mocha')
  s.add_development_dependency('awesome_print')
end


