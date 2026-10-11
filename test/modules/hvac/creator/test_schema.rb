require 'json'
require_relative '../../../helpers/minitest_helper'

# Checks on the creator schema itself: that it is well formed, that every reference resolves, and
# that it describes the model a field produces rather than the code that consumes it.
class TestHVACCreatorSchema < Minitest::Test
  SCHEMA_PATH = File.expand_path('../../../../lib/openstudio-standards/hvac/hvac_creator_schema.json', __dir__).freeze

  # Ruby method, file, module and namespace names. A schema is the contract for the input format, so
  # a description naming the code that reads it goes stale the moment that code is renamed - and
  # tells a spec author nothing about the model the field produces.
  IMPLEMENTATION_REFERENCE = /
    \b\w+\.rb\b                 # a source file
    | OpenstudioStandards       # the module
    | \bmodel_add_\w+           # a legacy system creator
    | \bmodel_get_or_add_\w+
    | \bcreate_[a-z_]+          # a component creator
    | ::                        # a Ruby namespace
  /x.freeze

  def setup
    @schema = JSON.parse(File.read(SCHEMA_PATH))
  end

  def test_schema_is_valid_json
    assert_kind_of(Hash, @schema)
    assert_equal('https://json-schema.org/draft/2020-12/schema', @schema['$schema'])
  end

  # Every $ref points at a definition that exists: a typo silently disables validation of whatever
  # the reference guards, so nothing else would notice.
  def test_every_ref_resolves
    unresolved = refs.reject { |ref| resolves?(ref) }
    assert_empty(unresolved.uniq, "unresolved $ref values: #{unresolved.uniq.join(', ')}")
  end

  def test_schema_uses_only_local_refs
    external = refs.reject { |ref| ref.start_with?('#/') }
    assert_empty(external.uniq, "the schema should be self-contained; external refs: #{external.uniq.join(', ')}")
  end

  # Every definition is reachable, so a $defs entry left behind by a rename does not linger.
  def test_no_orphaned_definitions
    referenced = refs.filter_map { |ref| ref[%r{\A\#/\$defs/(.+)\z}, 1] }.to_set
    orphans = @schema['$defs'].keys.reject { |name| referenced.include?(name) }
    assert_empty(orphans, "definitions nothing references: #{orphans.join(', ')}")
  end

  # Section 0.8: descriptions state the model outcome, not the implementation that consumes them.
  def test_descriptions_name_no_implementation
    offenders = []
    walk(@schema, '') do |path, node|
      next unless node.is_a?(Hash)

      description = node['description']
      next unless description.is_a?(String)

      description.scan(IMPLEMENTATION_REFERENCE) { |match| offenders << "#{path}: '#{match}'" }
    end
    assert_empty(offenders, "descriptions naming implementation:\n  #{offenders.join("\n  ")}")
  end

  # Every component type the schema offers can actually be built, and every builder is offered.
  def test_obj_type_enum_matches_the_registry
    registered = OpenstudioStandards::HVAC::ComponentFactory::COMPONENT_BUILDERS.keys.to_set
    declared = @schema['$defs']['hvacComponent']['properties']['obj_type']['enum'].to_set
    assert_empty((declared - registered).to_a, 'obj_type values in the schema with no registered builder')
    assert_empty((registered - declared).to_a, 'registered builders missing from the obj_type enum')
  end

  def test_spm_type_enum_matches_the_registry
    registered = OpenstudioStandards::HVAC::SetpointManagerFactory::SETPOINTMANAGER_BUILDERS.keys.to_set
    declared = @schema['$defs']['setpointManager']['properties']['spm_type']['enum'].to_set
    assert_empty((declared - registered).to_a, 'spm_type values in the schema with no registered builder')
    assert_empty((registered - declared).to_a, 'registered setpoint manager builders missing from the spm_type enum')
  end

  private

  def refs
    @refs ||= [].tap do |found|
      walk(@schema, '') do |_path, node|
        found << node['$ref'] if node.is_a?(Hash) && node['$ref'].is_a?(String)
      end
    end
  end

  def resolves?(ref)
    return false unless ref.start_with?('#/')

    ref.delete_prefix('#/').split('/').reduce(@schema) do |node, key|
      return false unless node.is_a?(Hash) && node.key?(key)

      node[key]
    end
    true
  end

  def walk(node, path, &block)
    block.call(path, node)
    case node
    when Hash then node.each { |key, value| walk(value, "#{path}/#{key}", &block) }
    when Array then node.each_with_index { |value, index| walk(value, "#{path}[#{index}]", &block) }
    end
  end
end
