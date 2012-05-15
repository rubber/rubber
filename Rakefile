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

  changelog_file = 'CHANGELOG'
  entries = ""
  
  helper = Bundler::GemHelper.new(Dir.pwd)
  current_version = "v#{helper.gemspec.version}"
  starting_version = nil
  ending_version = nil, ending_version_name = nil

  if ENV['VERSION']
    ver = ENV['VERSION']
    first_ver, second_ver = ver.split("..")
    starting_version = "v#{first_ver.gsub(/^[^\d]*/, '')}" if ! first_ver.nil? && first_ver.size > 0
    ending_version = "v#{second_ver.gsub(/^[^\d]*/, '')}" if ! second_ver.nil? && second_ver.size > 0
    ending_version_name = ending_version if ending_version
  end
  
  # If we already have a changelog, make the starting_version be the
  # last one in the changelog
  #
  if ! starting_version && File.exist?(changelog_file)
    entries = File.read(changelog_file)
    head = entries.split.first
    if head =~ /(\d\.\d\.\d).*/
      starting_version = "v#{$1}"
      
      if current_version == starting_version
        puts "WARN: gemspec version is the same as most recent changelog: #{current_version}"
      end
    end
  end
  
   # Get a list of current tags
  tags = `git tag -l`.split
  tags = tags.sort_by {|t| t[1..-1].split(".").collect {|s| s.to_i } }
  newest_tag = tags[-1]

  if current_version == newest_tag
    # When generating CHANGELOG after release, we want the last tag as the ending version
    ending_version = newest_tag
    ending_version_name = newest_tag
  else
    # When generating CHANGELOG before release, we want the current ver as the ending version
    ending_version = "HEAD"
    ending_version_name = current_version
  end

  if starting_version
    version_selector = "#{starting_version}..#{ending_version}"
  else
    puts "WARN: No starting version, dumping entire history, try: rake changelog VERSION=v1.2.3"
    version_selector = ""
  end
  
  # Generate changelog from repo
  puts "Generating a changelog for #{version_selector}"
  log=`git log --pretty='format:%s <%h>' #{version_selector}`.lines.to_a

  # Strip out maintenance entries
  log = log.delete_if do |l|
     l =~ /^Regenerated? gemspec/ ||
         l =~ /^version bump/i ||
         l =~ /^bump version/i ||
         l =~ /^Updated changelog/ ||
         l =~ /^Merged? branch/
  end
  
  # Add templates user needs to run vulcanize for
  log = log.collect do |l|
    if l =~ /<(.+)>/
      ver = $1
      files = `git diff --name-only #{ver}^1 #{ver}`.lines.to_a
      templates = files.collect {|f| f =~ /templates\/([^\/]+)\// ? $1 : nil}.compact.sort.uniq
      templates << 'core'  if templates.size == 0
      l = "[#{templates.join(", ")}] #{l}"
    end
    l
  end
  
  # sort so core comes first
  log = log.sort_by {|s| s =~ /\[.*core.*\]/ ? "" : s }  
  
  # Write out changelog file
  File.open(changelog_file, 'w') do |out|
    ver_title = ending_version_name.gsub(/^v/, '') + " (#{Time.now.strftime("%m/%d/%Y")})"
    out.puts ver_title
    out.puts "-" * ver_title.size
    out.puts "\n"
    out.puts log
    out.puts "\n"
    out.puts entries
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
