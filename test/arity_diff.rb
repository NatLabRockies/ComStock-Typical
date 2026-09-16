# Compare the parameter list of every method present in both this tree and openstudio-standards.
# Removing a standards family can quietly drop a parameter from a surviving method — the NECB
# removal took `necb_ref_hp` out of six of them — and a caller that still passes the old number of
# arguments fails only when that code path runs. This finds every such method in one pass.
#
#   UPSTREAM_ROOT=/path/to/openstudio-standards openstudio execute_ruby_script test/arity_diff.rb
#
FORK = ENV['FORK_ROOT'] || File.expand_path('..', __dir__)
UP   = ENV['UPSTREAM_ROOT'].to_s
abort 'Set UPSTREAM_ROOT to an openstudio-standards checkout.' if UP.empty?

def sigs(root)
  out = {}
  Dir.glob("#{root}/lib/**/*.rb").each do |path|
    rel = path.sub("#{root}/", '')
    File.readlines(path).each do |line|
      next unless line =~ /^\s*def\s+(self\.)?([a-z_][A-Za-z0-9_]*[?!=]?)\s*\(([^)]*)\)/
      name = "#{Regexp.last_match(1)}#{Regexp.last_match(2)}"
      params = Regexp.last_match(3).split(',').map(&:strip)
      out["#{rel}##{name}"] = params
    end
  end
  out
end

f = sigs(FORK)
u = sigs(UP)
changed = f.keys.select { |k| u.key?(k) && u[k] != f[k] }
puts "methods present in both trees: #{(f.keys & u.keys).size}"
puts "parameter lists that changed:  #{changed.size}"
changed.sort.each do |k|
  puts "  #{k}"
  puts "      upstream: (#{u[k].join(', ')})"
  puts "      fork:     (#{f[k].join(', ')})"
end
