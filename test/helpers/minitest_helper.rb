=begin
require 'simplecov'
require 'codecov'

# Get the code coverage in html for local viewing
# and in JSON for CI codecov
if ENV['CI'] == 'true'
  SimpleCov.formatter = SimpleCov::Formatter::Codecov
else
  SimpleCov.formatter = SimpleCov::Formatter::HTMLFormatter
end

# Ignore some of the code in coverage testing
SimpleCov.start do
  add_filter '/.idea/'
  add_filter '/.yardoc/'
  add_filter '/data/'
  add_filter '/doc/'
  add_filter '/docs/'
  add_filter '/pkg/'
  add_filter '/test/'
  add_filter '/hvac_sizing/'
  add_filter 'version'  
end
=end

$LOAD_PATH.unshift File.expand_path('../../../lib', __FILE__)
require 'minitest/autorun'
if ENV['CI'] == 'true'
  require 'minitest/ci'
  puts "Saving test results to #{Minitest::Ci.report_dir}"
end
require 'minitest/reporters'
require 'minitest/reporters/base_reporter'
require 'minitest/reporters/spec_reporter'

require 'openstudio'
require 'openstudio/measure/ShowRunnerOutput'
require 'json'
require 'fileutils'

# Require local version instead of installed version for developers
begin
  require_relative '../../lib/openstudio-standards.rb'
  puts 'DEVELOPERS OF OPENSTUDIO-STANDARDS: Requiring code directly instead of using installed gem.  This avoids having to run rake install every time you make a change.' 
rescue LoadError
  require 'openstudio-standards'
  puts 'Using installed openstudio-standards gem.' 
end

# Control for the tests that run EnergyPlus.
#
# 50 of the suite's 664 tests take 90% of its 108 minutes, and nearly all of that is EnergyPlus:
# sizing runs, and annual runs whose results the test then reads back. That is fine in CI and
# painful when iterating on a single module, so a test that simulates can be asked to skip.
#
# Simulations run by default, so CI, the archived Phase 3 baseline and anyone who sets nothing
# are unaffected. Set SKIP_SIMULATION_TESTS to a true-ish value to skip them:
#
#   SKIP_SIMULATION_TESTS=true openstudio execute_ruby_script test/baseline_run.rb
#
# A skipped test is reported as a skip, not a pass, so a run that skipped them cannot be mistaken
# for a full one. Do not use this to get a green run: the simulation tests are the only ones that
# check a model actually holds setpoint.
module OpenstudioStandardsTesting
  SKIP_SIMULATIONS = %w[1 true yes on].include?(ENV['SKIP_SIMULATION_TESTS'].to_s.strip.downcase)

  def self.simulations_enabled?
    !SKIP_SIMULATIONS
  end
end

class Minitest::Test
  # Call from the setup of any test class that runs EnergyPlus.
  def skip_unless_simulations_enabled
    return if OpenstudioStandardsTesting.simulations_enabled?

    skip 'SKIP_SIMULATION_TESTS is set; this test runs EnergyPlus'
  end
end

if OpenstudioStandardsTesting::SKIP_SIMULATIONS
  puts 'SKIP_SIMULATION_TESTS is set: tests that run EnergyPlus will be skipped, not run.'
end

# Set the output reporting format based on the run environment
if ENV['RM_INFO'] || ENV['TEAMCITY_RAKE_RUNNER_MODE'] # RubyMine
  puts "Running tests from RubyMine, using RubyMine test reporter."
  ENV.delete('RM_INFO') # Delete this environment variable because it forces use of only RubyMineReporter
  Minitest::Reporters.use! [Minitest::Reporters::RubyMineReporter.new]
  # line below for PNNL local testing
  # Minitest::Reporters.use! [Minitest::Reporters::RubyMineReporter.new, Minitest::Reporters::JUnitReporter.new(reports_dir="test/reports", empty=false)] 
elsif ENV['JENKINS_HOME'] # Jenkins
  puts "Running tests from Jenkins, using JUnit XML test reporter and console-based test reporter."
  Minitest::Reporters.use! [Minitest::Reporters::SpecReporter.new, Minitest::Reporters::JUnitReporter.new(reports_dir = "test/reports", empty = false)]
else # Terminal or other
  puts "Running tests from terminal, using console-based test reporter."
  Minitest::Reporters.use! [Minitest::Reporters::SpecReporter.new]
  # line below for PNNL local testing
  # Minitest::Reporters.use! [Minitest::Reporters::SpecReporter.new, Minitest::Reporters::JUnitReporter.new(reports_dir="test/reports", empty=false)] 
end
