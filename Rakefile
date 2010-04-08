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
    s.add_dependency 'capistrano', '>= 2.4.0'
    s.add_dependency 'amazon-ec2', '>= 0.9.0'
    s.add_dependency 'aws-s3'
    s.add_dependency 'nettica'
    s.add_dependency 'zerigo_dns'
    s.add_dependency 'railties', '3.0.0.beta2'
  end
  Jeweler::GemcutterTasks.new
rescue LoadError
  puts "Jeweler not available. Install it with: sudo gem install jeweler"
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

task :changelog do

  changelog_file = 'CHANGELOG'
  entries = ""

  # Get a list of current tags
  tags = `git tag -l`.split

  # If we already have a changelog, make the last tag be the
  # last one in the changelog, and the next one be the one
  # following that in the tag list
  if File.exist?(changelog_file)
    entries = File.read(changelog_file)
    head = entries.split.first
    if head =~ /\d\.\d\.\d/
      last_tag = "v#{head}"
      idx = tags.index(last_tag)
      current_tag = tags[idx + 1]
    end
  end

  # Figure out last/current tags and do some validation
  last_tag ||= tags[-2]
  current_tag ||= tags[-1]

  if last_tag.nil? && current_tag.nil?
    puts "Cannot generate a changelog without first tagging your repository"
    puts "Tags should be in the form vN.N.N"
    exit
  end

  if last_tag == current_tag
    puts "Nothing to do for equal revisions: #{last_tag}..#{current_tag}"
    exit
  end


  # Generate changelog from repo
  log=`git log --pretty='format:%s <%h> [%cn]' #{last_tag}..#{current_tag}`

  # Strip out maintenance entries
  log = log.to_a.delete_if {|l| l =~ /^Regenerated gemspec/ || l =~ /^Version bump/ || l =~ /^Updated changelog/ }

  # Write out changelog file
  File.open(changelog_file, 'w') do |out|
    out.puts current_tag.gsub(/^v/, '')
    out.puts "-----"
    out.puts "\n"
    out.puts log
    out.puts "\n"
    out.puts entries
  end

  # Commit and push
  sh "git ci -m'Updated changelog' #{changelog_file}"
  sh "git push"
end

task :my_release => ['release', 'changelog', 'gemcutter:release'] do
end
