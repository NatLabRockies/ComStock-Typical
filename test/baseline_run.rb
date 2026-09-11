# Phase 3 baseline: run the kept test set in one OpenStudio CLI process, so the ~52s
# interpreter startup is paid once rather than 125 times.
STDOUT.sync = true
ROOT = ENV['CHECK_ROOT'] || File.expand_path('..', __dir__)
OUT  = ENV['BASELINE_OUT'] || "#{Dir.pwd}/baseline_results.txt"

require 'openstudio'
$LOAD_PATH.unshift("#{ROOT}/lib")
$LOAD_PATH.unshift("#{ROOT}/test/helpers")

files = []
%w[test/modules test/90_1_general test/os_stds_methods].each do |dir|
  files += Dir.glob("#{ROOT}/#{dir}/**/test_*.rb").sort
end

loaded = []
load_errors = []
files.each do |f|
  begin
    require f
    loaded << f
  rescue Exception => e
    load_errors << "#{f.sub("#{ROOT}/", '')}: #{e.class}: #{e.message.to_s.lines.first.to_s.strip}"
  end
end

File.write(OUT, ([
  'ComStock-Typical baseline test run (end of Phase 3)',
  "test files found:  #{files.size}",
  "loaded cleanly:    #{loaded.size}",
  "failed to load:    #{load_errors.size}",
  ''
] + load_errors.map { |e| "  LOAD ERROR #{e}" }).join("\n") + "\n")
puts "LOADED #{loaded.size}/#{files.size} test files; #{load_errors.size} load errors"
load_errors.each { |e| puts "  LOAD ERROR #{e}" }
