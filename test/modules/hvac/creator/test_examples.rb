require 'json'
require_relative '../../../helpers/minitest_helper'

# The example specs are documentation that has to keep working: each is parsed, validated against the
# schema, and built into a model. They use plain zone names ("Zone 1") so they read as examples
# rather than as fixtures of one particular building, and the model here is built to match.
class TestHVACCreatorExamples < Minitest::Test
  EXAMPLES_DIR = File.expand_path('../../../../lib/openstudio-standards/hvac/creator/examples', __dir__).freeze
  SCHEMA_PATH = File.expand_path('../../../../lib/openstudio-standards/hvac/hvac_creator_schema.json', __dir__).freeze

  def setup
    @hvac = OpenstudioStandards::HVAC
  end

  def example_paths
    paths = Dir.glob("#{EXAMPLES_DIR}/*.json").sort
    refute_empty(paths, 'no example specs found')
    paths
  end

  # Two zones, named as the examples name them.
  def model_with_zones(count = 2)
    model = OpenStudio::Model::Model.new
    Array.new(count) do |index|
      zone = OpenStudio::Model::ThermalZone.new(model)
      zone.setName("Zone #{index + 1}")
      space = OpenStudio::Model::Space.new(model)
      space.setThermalZone(zone)
      zone
    end
    model
  end

  def test_every_example_is_valid_json_with_identity
    example_paths.each do |path|
      spec = JSON.parse(File.read(path))
      name = File.basename(path)
      assert(spec['schema_version'], "#{name} should state a schema_version")
      assert(spec['custom_system_type'], "#{name} should state a custom_system_type")
      assert(spec['description'].to_s.length > 40, "#{name} should describe what it demonstrates")
    end
  end

  # Structural validation is the factory's own gate, so run it on the examples explicitly: an example
  # that fails it would be documentation teaching a spec the factory rejects.
  def test_every_example_passes_structural_validation
    example_paths.each do |path|
      spec = OpenstudioStandards::HVAC::ComponentFactory.deep_symbolize(JSON.parse(File.read(path)))
      warnings = OpenstudioStandards::HVAC::Validation.check(spec)
      undeclared = warnings.grep(/does not declare/)
      assert_empty(undeclared, "#{File.basename(path)} references names it does not declare: #{undeclared.join(', ')}")
    rescue ArgumentError => e
      flunk("#{File.basename(path)} failed validation: #{e.message}")
    end
  end

  # Validation against the JSON Schema itself, when the gem is available. Skipped rather than failed
  # when it is not, since json_schemer is a development dependency.
  def test_every_example_validates_against_the_schema
    begin
      require 'json_schemer'
    rescue LoadError
      skip('json_schemer is not installed')
    end

    schemer = JSONSchemer.schema(JSON.parse(File.read(SCHEMA_PATH)))
    example_paths.each do |path|
      errors = schemer.validate(JSON.parse(File.read(path))).map do |error|
        "#{error['data_pointer']}: #{error['type']}"
      end
      assert_empty(errors.first(10), "#{File.basename(path)} does not validate: #{errors.first(10).join('; ')}")
    end
  end

  def test_every_example_builds_a_model
    example_paths.each do |path|
      model = model_with_zones
      spec = JSON.parse(File.read(path))
      @hvac.apply_hvac(model, spec)
      refute_empty(model.getModelObjects, "#{File.basename(path)} built nothing")
      assert_equal(spec['custom_system_type'],
                   model.getBuilding.additionalProperties.getFeatureAsString('custom_system_type').get,
                   "#{File.basename(path)} should record its identity on the building")
    end
  end

  # Every example must translate, so an example cannot teach a spec that produces a model EnergyPlus
  # would reject.
  def test_every_example_forward_translates
    example_paths.each do |path|
      model = model_with_zones
      @hvac.apply_hvac(model, JSON.parse(File.read(path)))
      translator = OpenStudio::EnergyPlus::ForwardTranslator.new
      translator.translateModel(model)
      messages = translator.errors.map(&:logMessage)
      assert_empty(messages, "#{File.basename(path)} does not translate: #{messages.join("\n")}")
    end
  end

  def test_psz_ac_example_builds_its_air_loop_and_unitary
    model = model_with_zones
    @hvac.apply_hvac(model, JSON.parse(File.read("#{EXAMPLES_DIR}/psz_ac.json")))
    assert_equal(1, model.getAirLoopHVACs.size)
    assert_equal(1, model.getAirLoopHVACUnitarySystems.size)
    unitary = model.getAirLoopHVACUnitarySystems.first
    assert_equal('Zone 1', unitary.controllingZoneorThermostatLocation.get.name.get)
  end

  def test_vav_example_builds_three_plant_loops_and_two_chillers
    model = model_with_zones
    @hvac.apply_hvac(model, JSON.parse(File.read("#{EXAMPLES_DIR}/vav_chw_hw.json")))
    assert_equal(3, model.getPlantLoops.size)
    assert_equal(2, model.getChillerElectricEIRs.size)
    # one main cooling coil, one preheat coil, and a reheat coil per zone
    assert_equal(1, model.getCoilCoolingWaters.size)
    assert_equal(3, model.getCoilHeatingWaters.size)
    # the waterside economizer is a deferred pass, applied after every loop exists
    assert_equal(1, model.getHeatExchangerFluidToFluids.size)
  end

  def test_wshp_example_installs_the_ground_heat_exchanger_ems
    model = model_with_zones
    @hvac.apply_hvac(model, JSON.parse(File.read("#{EXAMPLES_DIR}/wshp_ground_loop.json")))
    assert_equal(1, model.getPlantComponentTemperatureSources.size)
    assert_equal(1, model.getEnergyManagementSystemPrograms.size)
    assert_equal(2, model.getZoneHVACWaterToAirHeatPumps.size)
  end

  def test_vrf_example_attaches_both_terminals_to_one_condensing_unit
    model = model_with_zones
    @hvac.apply_hvac(model, JSON.parse(File.read("#{EXAMPLES_DIR}/vrf_doas.json")))
    assert_equal(1, model.getAirConditionerVariableRefrigerantFlows.size)
    assert_equal(2, model.getAirConditionerVariableRefrigerantFlows.first.terminals.size)
  end
end
