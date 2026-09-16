require 'bundler/gem_tasks'
require 'json'
require 'fileutils'
begin
  Bundler.setup
rescue Bundler::BundlerError => e
  warn e.message
  warn 'Run `bundle install` to install missing gems'
  exit e.status_code
end

require 'rake/testtask'
namespace :test do
  full_file_list = nil
  if File.exist?('test/ci_tests.txt')
    # load test files from file.
    full_file_list = FileList.new(File.readlines('test/ci_tests.txt'))
    # Select only .rb files that exist
    full_file_list.select! { |item| item.include?('rb') && File.exist?(File.absolute_path("test/#{item.strip}")) }
    full_file_list.map! { |item| File.absolute_path("test/#{item.strip}") }
    File.open('test/ci_tests.json', 'w') do |f|
      f.write(JSON.pretty_generate(full_file_list.to_a))
    end
  else
    puts 'Could not find list of files to test at test/ci_tests.txt'
    return false
  end

  desc 'parallel_run_all_tests_locally'
  Rake::TestTask.new('parallel_run_all_tests_locally') do |t|
    # Make an empty test/reports directory
    report_dir = 'test/reports'
    FileUtils.rm_rf(report_dir)
    Dir.mkdir(report_dir)
    file_list = FileList.new('test/parallel_run_all_tests_locally.rb')
    t.libs << 'test'
    t.test_files = file_list
    t.verbose = false
  end
end

# The spreadsheet pipeline went with the fork. The 90.1 data comes from the building energy
# standards database at https://github.com/pnnl/building-energy-standards-data, the typical data
# is edited as JSON beside the module that reads it, and the remaining spreadsheet-generated
# family, DEER, leaves when Title 24 replaces it. The data:update task and
# data/standards/manage_OpenStudio_Standards.rb went with it.

# The OpenStudio-installer library export stays with openstudio-standards (decision D9): no test
# here invokes it and this gem ships no installer libraries. The library:export task and
# data/standards/export_OpenStudio_libraries.rb went with it.

require 'yard'
desc 'Generate the documentation'
YARD::Rake::YardocTask.new(:doc) do |t|
  t.stats_options = ['--list-undoc']
end

desc 'Show the documentation in a web browser'
task 'doc:show' => [:doc] do
  link = "#{Dir.pwd}/doc/index.html"
  if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
    system "start #{link}"
  elsif RbConfig::CONFIG['host_os'] =~ /darwin/
    system "open #{link}"
  elsif RbConfig::CONFIG['host_os'] =~ /linux|bsd/
    system "xdg-open #{link}"
  end
end

require 'rubocop/rake_task'
desc 'Check the code for style consistency'
RuboCop::RakeTask.new(:rubocop) do |t|
  # Make a folder for the output
  out_dir = '.rubocop'
  FileUtils.mkdir_p(out_dir)
  # Output both XML (CheckStyle format) and HTML
  t.options = ["--out=#{out_dir}/rubocop-results.xml", '--format=h', "--out=#{out_dir}/rubocop-results.html", '--format=offenses', "--out=#{out_dir}/rubocop-summary.txt"]
  t.requires = ['rubocop/formatter/checkstyle_formatter']
  t.formatters = ['RuboCop::Formatter::CheckstyleFormatter']
  # don't abort rake on failure
  t.fail_on_error = false
end

desc 'Show the rubocop output in a web browser'
task 'rubocop:show' => [:rubocop] do
  link = "#{Dir.pwd}/.rubocop/rubocop-results.html"
  if RbConfig::CONFIG['host_os'] =~ /mswin|mingw|cygwin/
    system "start #{link}"
  elsif RbConfig::CONFIG['host_os'] =~ /darwin/
    system "open #{link}"
  elsif RbConfig::CONFIG['host_os'] =~ /linux|bsd/
    system "xdg-open #{link}"
  end
end
