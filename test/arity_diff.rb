# Phase 1-3 removed NECB/DEER/PRM-only parameters from some surviving methods. Any method whose
# parameter list changed is a place a stale caller can still pass the old number of arguments.
FORK = ENV['FORK_ROOT'] || File.expand_path('..', __dir__)
UP   = ENV['UPSTREAM_ROOT'] || 'C:/Repos/NREL/openstudio-standards-working'

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
