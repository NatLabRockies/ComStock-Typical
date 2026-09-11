lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'openstudio-standards/version'

Gem::Specification.new do |spec|
  spec.name          = 'comstock-typical'
  spec.version       = OpenstudioStandards::VERSION
  spec.authors       = ['Mark Adams', 'Yeonjin Bae', 'Carlo Bianchi', 'Jeff Blake', 'Yixing Chen', 'Matthew Dahlhausen', 'Carlos Duarte', 'Sarah Gilani', 'David Goldwasser', 'Kamel Haddad', 'Piljae Im', 'Chris Kirney', 'Matt Leach', 'Xuechen (Jerry) Lei', 'Jeremy Lerond', 'Nicholas Long', 'Phylroy Lopez', 'Iain MacDonald', 'Daniel Macumber', 'Doug Maddox', 'Mini Maholtra', 'Julien Marrec', 'Juan Gonzalez Matamoros', 'Maria Mottillo', 'Andrew Parker', 'Padmassun Rajakareyar', 'Eric Ringold', 'Matt Steen', 'Kaiyu Sun', 'Weilie Xu', 'Yunyang Ye', 'Jian Zhang']
  spec.email         = ['Eric.Ringold@nlr.gov']
  spec.homepage      = 'https://github.com/NatLabRockies/ComStock-Typical'
  spec.summary       = 'Creates OpenStudio models of typical buildings, applying code minimums from ASHRAE 90.1 and California Title 24.'
  spec.description   = 'ComStock-Typical generates typical commercial building energy models for ComStock. It creates a building from user geometry or from a custom building specification, populates loads, schedules, ventilation, service water heating and HVAC from vintage-agnostic typical data, and applies code-minimum performance from the ASHRAE 90.1 and California Title 24 standards data. Forked from openstudio-standards; the prototype, Appendix G PRM and NECB functionality stays there.'
  spec.license       = 'Modified BSD License'
  spec.metadata = {
    "documentation_uri" => "https://github.com/NatLabRockies/ComStock-Typical"
  }

  spec.required_ruby_version = '>= 2.0.0'
  spec.required_rubygems_version = '>= 1.3.6'
  spec.files = Dir['LICENSE.md', 'lib/**/*', 'data/**/*']
  spec.require_paths = ['lib']
  if RUBY_VERSION < '2.3'
    spec.add_development_dependency 'bundler', '~> 1.9'
    spec.add_development_dependency 'nokogiri', '<= 1.6.8.1'
    spec.add_development_dependency 'parallel_tests', '<= 2.32.0'
  elsif RUBY_VERSION < '2.7'
    spec.add_development_dependency 'public_suffix', '~> 4.0.7'
    spec.add_development_dependency 'nokogiri', '<= 1.11.7'
    spec.add_development_dependency 'bundler', '~> 2.1'
    spec.add_development_dependency 'parallel_tests', '~> 3.0.0'
  elsif RUBY_VERSION < '3.2'
    spec.add_development_dependency 'nokogiri', '<= 1.15.6'
    spec.add_development_dependency 'public_suffix', '~> 5.1.1'
    spec.add_development_dependency 'bundler', '~> 2.1.4'
    spec.add_development_dependency 'parallel_tests', '~> 3.7.0'
  else
    spec.add_development_dependency 'bundler', '~> 2.4.10'
    spec.add_development_dependency 'nokogiri', '~> 1.16'
    spec.add_development_dependency 'parallel_tests', '~> 3.7.0'
  end
  spec.add_development_dependency 'codecov'
  spec.add_development_dependency 'json_schemer', '~> 2.0'
  spec.add_development_dependency 'minitest', '~> 5.26.0'
  spec.add_development_dependency 'minitest-ci'
  spec.add_development_dependency 'minitest-parallel_fork'
  spec.add_development_dependency 'minitest-reporters', '~> 1.7.1'
  spec.add_development_dependency 'openstudio-api-stubs'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rexml', '~> 3.4.4'
  spec.add_development_dependency 'rubocop', '~> 1.81.1'
  spec.add_development_dependency 'rubocop-checkstyle_formatter', '~> 0.6.0'
  spec.add_development_dependency 'ruby-progressbar'
  spec.add_development_dependency 'rubyXL', '~> 3.4'
  spec.add_development_dependency 'simplecov', '0.22.0'
  spec.add_development_dependency 'yard', '~> 0.9'
  # spec.add_development_dependency 'aws-sdk-s3'
  # spec.add_development_dependency 'git-revision'
  # spec.add_development_dependency 'bundler-audit'
  # Add solargraph for code completion and documentation generation, and MCP support.
  # spec.add_development_dependency 'solargraph'
end
