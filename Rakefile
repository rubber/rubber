gemfile = File.expand_path(File.join(__FILE__, '..', 'Gemfile'))
if File.exist?(gemfile) && ENV['BUNDLE_GEMFILE'].nil?
  puts "Respawning with 'bundle exec rake'"
  exec("bundle", "exec", "rake", *ARGV)
end

require 'bundler'
Bundler::GemHelper.install_tasks

require 'rake'
require 'rake/testtask'

task :my_release => ['changelog', 'release'] do
end

task :changelog do

  helper = Bundler::GemHelper.new(Dir.pwd)
  version = "v#{helper.gemspec.version}"

  changelog_file = 'CHANGELOG'
  entries = ""

  # Get a list of current tags
  tags = `git tag -l`.split
  tags = tags.sort_by {|t| t[1..-1].split(".").collect {|s| s.to_i } }
  newest_tag = tags[-1]

  if version == newest_tag
    puts "You need to update version, same as most recent tag: #{version}"
    exit
  end

  # If we already have a changelog, make the last tag be the
  # last one in the changelog, and the next one be the one
  # following that in the tag list
  newest_changelog_version = nil
  if File.exist?(changelog_file)
    entries = File.read(changelog_file)
    head = entries.split.first
    if head =~ /\d\.\d\.\d/
      newest_changelog_version = "v#{head}"

      if version == newest_changelog_version
        puts "You need to update version, same as most recent changelog: #{version}"
        exit
      end

    end
  end

  # Generate changelog from repo
  log=`git log --pretty='format:%s <%h> [%cn]' #{newest_tag}..#{HEAD}`

  # Strip out maintenance entries
  log = log.lines.to_a.delete_if do |l|
     l =~ /^Regenerated? gemspec/ ||
         l =~ /^version bump/i ||
         l =~ /^Updated changelog/ ||
         l =~ /^Merged? branch/
  end

  # Write out changelog file
  File.open(changelog_file, 'w') do |out|
    out.puts version.gsub(/^v/, '')
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

desc 'Test the rubber plugin.'
Rake::TestTask.new(:test) do |t|
  t.libs << 'lib'
  t.libs << 'test'
  t.pattern = 'test/**/*_test.rb'
  t.verbose = true
end

desc 'Default: run unit tests.'
task :default => :test
