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
    s.description = "The rubber plugin enables relatively complex multi-instance deployments of RubyOnRails applications to Amazon's Elastic Compute Cloud (EC2).  Like capistrano, rubber is role based, so you can define a set of configuration files for a role and then assign that role to as many concrete instances as needed. One can also assign multiple roles to a single instance. This lets one start out with a single ec2 instance (belonging to all roles), and add new instances into the mix as needed to scale specific facets of your deployment, e.g. adding in instances that serve only as an 'app' role to handle increased app server load."
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

task :release => :changelog
task :gemcutter => :release

task :gemcutter do
  rubber_yml = 'generators/vulcanize/templates/base/config/rubber/rubber.yml'
  yml = File.join(File.dirname(__FILE__), rubber_yml)
  gcyml = File.read(yml).gsub('wr0ngway-rubber', 'rubber')
  File.open(yml, 'w') do |f|
    f.write(gcyml)
  end
  sh "gem build rubber.gemspec"
  sh "gem push rubber-*.gem"
  sh "git co #{rubber_yml}"
  sh "rm -f rubber-*.gem"
end

task :changelog do

  tags = `git tag -l`.split

  out_file = ENV['OUTPUT'] || 'CHANGELOG'
  if out_file.size > 0
    entries = File.read(out_file)
    head = entries.split.first
    if head =~ /\d\.\d\.\d/
      last_tag = "v#{head}"
      idx = tags.index(last_tag)
      current_tag = tags[idx + 1] rescue nil
    end
  else
    entries = ""
    out_file=$stdout
  end

  last_tag = ENV['LAST_TAG'] || last_tag || tags[-2]
  current_tag = ENV['CURRENT_TAG'] || current_tag || tags[-1]

  if last_tag == current_tag
    puts "Nothing to do for equal revisions: #{last_tag}..#{current_tag}"
    exit
  end
  
  log=`git log --pretty='format:%s <%h> [%cn]' #{last_tag}..#{current_tag}`
  log = log.to_a.delete_if {|l| l =~ /^Regenerated gemspec/ || l =~ /^Version bump/ || l =~ /^Updated changelog/ }

  out = File.open(out_file, 'w')
  
  out.puts current_tag.gsub(/^v/, '')
  out.puts "-----"
  out.puts "\n"
  out.puts log
  out.puts "\n"
  out.puts entries

  if out_file != $stdout
    sh "git ci -m'Updated changelog' #{out_file}"
    sh "git push #{out_file}"
  end
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

