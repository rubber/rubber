require 'rake'
require 'rake/testtask'

begin
  require 'jeweler'
  Jeweler::Tasks.new do |s|
    s.name = "rubber"
    s.executables = "vulcanize"
    s.summary = "A capistrano plugin for managing multi-instance deployments to the cloud (ec2)"
    s.email = "matt@conwaysplace.com"
    s.homepage = "http://github.com/wr0ngway/rubber"
    s.description = "The rubber plugin enables relatively complex multi-instance deployments of RubyOnRails applications to AmazonÕs Elastic Compute Cloud (EC2).  Like capistrano, rubber is role based, so you can define a set of configuration files for a role and then assign that role to as many concrete instances as needed. One can also assign multiple roles to a single instance. This lets one start out with a single ec2 instance (belonging to all roles), and add new instances into the mix as needed to scale specific facets of your deployment, e.g. adding in instances that serve only as an 'app' role to handle increased app server load."
    s.rubyforge_project = 'rubber'
    s.authors = ["Matt Conway"]
    s.files =  FileList["[A-Z][A-Z]*", "{bin,generators,lib,rails,recipes}/**/*"]
    s.add_dependency 'capistrano'
    s.add_dependency 'amazon-ec2', '>= 0.5.0'
    s.add_dependency 'aws-s3'
    s.add_dependency 'nettica'
    s.add_dependency 'httparty'
    s.add_dependency 'rails'
  end
  Jeweler::RubyforgeTasks.new
rescue LoadError
  puts "Jeweler not available. Install it with: sudo gem install technicalpickles-jeweler -s http://gems.github.com"
end

task :gemcutter do
  rubber_yml = 'generators/vulcanize/templates/base/config/rubber/rubber.yml'
  yml = File.join(File.dirname(__FILE__), rubber_yml)
  gcyml = File.read(yml).gsub('wr0ngway-rubber', 'rubber')
  File.open(yml) do |f|
    f.write(gcyml)
  end
  sh "gem build rubber.gemspec"
  sh "gem push rubber-*.gem"
  sh "git co #{rubber_yml}`"
end

desc 'Test the rubber plugin.'
Rake::TestTask.new(:test) do |t|
  t.libs << 'lib'
  t.libs << 'test'
  t.pattern = 'test/**/*_test.rb'
  t.verbose = true
end

desc 'Default: run unit tests.'
task :default => :test

