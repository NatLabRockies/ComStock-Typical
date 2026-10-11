require 'English'
require_relative '../../../helpers/minitest_helper'
require_relative 'legacy_reference'

# Phase 11 parity tests: each converted composer must build a model identical to its legacy
# model_add_* counterpart — same object counts by type, same object names, and the same values on a
# numeric checklist.
class TestHVACCreatorComposers < Minitest::Test
  def setup
    @hvac = OpenstudioStandards::HVAC
    @composers = OpenstudioStandards::HVAC::Composers
  end

  # The pre-conversion implementation, loaded from the commit the cutover started from.
  # Every model_add_* method now delegates to its composer, so comparing @hvac against
  # @composers would compare the composer with itself; the legacy side must come from here.
  def legacy_hvac
    skip("pinned legacy reference unavailable: #{LegacyReference.unavailable_reason}") unless LegacyReference.available?

    LegacyReference.hvac
  end

  # Assert two models are the same model: identical object counts by IDD type, identical object
  # names, and identical field values on every object the two models share by name.
  #
  # The field comparison exists because counts and names alone let real defects through - a field
  # that is populated in the legacy model and blank in the composed one leaves both counts and names
  # untouched. Two such defects reached EnergyPlus before this check existed: an air-source heat
  # pump's EMS sensor with an empty key name, and a unitary system with a blank controlling zone.
  def assert_model_parity(legacy, composed)
    assert_equal(type_counts(legacy), type_counts(composed), 'object counts by IDD type differ')
    assert_equal(object_names(legacy), object_names(composed), 'object names differ')
    diffs = field_diffs(legacy, composed)
    assert_empty(diffs, "object fields differ:\n  #{diffs.join("\n  ")}")
  end

  def type_counts(model)
    counts = Hash.new(0)
    model.getModelObjects.each { |object| counts[object.iddObjectType.valueName] += 1 }
    counts
  end

  def object_names(model)
    model.getModelObjects.map { |object| object.name.is_initialized ? object.name.get : nil }
         .compact
         .reject { |name| handle_style_name?(name) } # skip non-deterministic handle-style names
         .sort
  end

  def handle_style_name?(name)
    name.match?(/\A\{[0-9a-f-]+\}\z/)
  end

  # Compare every field of each object the two models share, keyed by IDD type and name.
  #
  # @return [Array<String>] one description per differing field
  def field_diffs(legacy, composed)
    composed_objects = objects_by_key(composed)
    objects_by_key(legacy).filter_map do |key, legacy_object|
      composed_object = composed_objects[key]
      next if composed_object.nil?

      object_field_diffs(key, legacy_object, composed_object)
    end.flatten
  end

  # Objects that can be matched across models: those carrying a name someone chose. A name
  # OpenStudio generated ("Curve Biquadratic 3") only records creation order, so two objects sharing
  # one across models are not necessarily the same object and comparing their fields is meaningless.
  # Those are left to the count and name checks.
  def objects_by_key(model)
    model.getModelObjects.each_with_object({}) do |object, hash|
      next unless object.name.is_initialized

      name = object.name.get
      next if handle_style_name?(name) || auto_generated_name?(object, name)
      # An availability manager list is created implicitly with its loop and named after the loop's
      # generated name, which the loop may later be renamed away from - so the list's name records
      # creation order too, and two lists sharing one across models need not be the same list.
      next if implicit_container?(object)

      hash["#{object.iddObjectType.valueName} '#{name}'"] = object
    end
  end

  def object_field_diffs(key, legacy_object, composed_object)
    field_count = [legacy_object.numFields, composed_object.numFields].max
    (0...field_count).filter_map do |index|
      next if field_name(legacy_object, index) == 'Handle'

      legacy_value = field_value(legacy_object, index)
      composed_value = field_value(composed_object, index)
      next if same_value?(legacy_value, composed_value)

      "#{key} field '#{field_name(legacy_object, index)}': legacy #{legacy_value.inspect}, composed #{composed_value.inspect}"
    end
  end

  # Numbers are compared as numbers, so "1" and "1.0" are the same value written two ways.
  def same_value?(legacy_value, composed_value)
    return true if legacy_value == composed_value

    legacy_number = numeric(legacy_value)
    composed_number = numeric(composed_value)
    return false if legacy_number.nil? || composed_number.nil?

    (legacy_number - composed_number).abs < 1.0e-9
  end

  def numeric(value)
    return nil unless value.is_a?(String)

    Float(value)
  rescue ArgumentError, TypeError
    nil
  end

  def field_name(object, index)
    field = object.iddObject.getField(index)
    field.is_initialized ? field.get.name : "field #{index}"
  end

  # A field's value with every object handle resolved to what it points at, so the comparison does
  # not trip over handles - which differ between any two models. Handles appear both as a whole
  # field value (a reference field) and embedded in text (an EMS program line), so they are resolved
  # wherever they occur; that makes an EMS program compare by the objects it drives rather than by
  # its handles.
  def field_value(object, index)
    # returnDefault: a field left empty reports its IDD default, so setting a field to the value it
    # would default to anyway does not read as a difference. Only values that actually differ do.
    raw = object.getString(index, true)
    return nil unless raw.is_initialized

    resolve_handles(raw.get, object.model)
  end

  def resolve_handles(value, model)
    resolved = value.gsub(/\{[0-9a-f-]{36}\}/i) do |handle|
      target = model.getObject(OpenStudio.toUUID(handle))
      target.is_initialized ? reference_label(target.get) : '(unresolved)'
    end
    # A reference field can hold the target's name outright rather than its handle; normalize the
    # generated names the same way, so a reference reads as what it points at rather than as the
    # order its target happened to be created in.
    named = model.getModelObjectByName(resolved)
    named.is_initialized ? reference_label(named.get) : resolved
  end

  # What a reference points at: the target's name, or its type when the name is one OpenStudio
  # generated (node and curve names follow creation order, not whether the model is correct).
  # Undecorated, so a legacy EMS line written with a handle matches a composed one written with
  # the object's own name - the two say the same thing.
  def reference_label(target)
    name = target.name.is_initialized ? target.name.get : nil
    return "(#{target.iddObject.name})" if name.nil? || auto_generated_name?(target, name) || implicit_container?(target)

    name
  end

  # Objects OpenStudio creates on a loop's behalf and names after the loop's generated name: which
  # of them a loop points at says nothing about whether the model is right.
  def implicit_container?(target)
    target.iddObject.name == 'OS:AvailabilityManagerAssignmentList'
  end

  # True when a name is the one OpenStudio assigns by default: the object's type words, optionally
  # followed by a number ("Node 7", "Thermal Zone 1").
  def auto_generated_name?(object, name)
    base = object.iddObject.name.sub(/\AOS:/, '').tr(':', ' ').gsub(/([a-z0-9])([A-Z])/, '\1 \2')
    name.match?(/\A#{Regexp.escape(base)}\s*\d*\z/)
  end

  # Build the same hot water loop with the legacy method and the composer.
  def build_pair(fuel_type, **kwargs)
    legacy = OpenStudio::Model::Model.new
    legacy_hvac.model_add_hw_loop(legacy, fuel_type, **kwargs)
    composed = OpenStudio::Model::Model.new
    @composers.hw_loop(composed, fuel_type, **kwargs)
    [legacy, composed]
  end

  def test_hw_loop_natural_gas_parity
    legacy, composed = build_pair('NaturalGas')
    assert_model_parity(legacy, composed)
  end

  def test_hw_loop_electric_boiler_parity
    legacy, composed = build_pair('Electricity')
    assert_model_parity(legacy, composed)
    assert_equal('Electricity', composed.getBoilerHotWaters.first.fuelType)
  end

  def test_hw_loop_constant_pump_parity
    legacy, composed = build_pair('NaturalGas', pump_spd_ctrl: 'Constant')
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getPumpConstantSpeeds.size)
  end

  def test_hw_loop_custom_temperatures_parity
    legacy, composed = build_pair('NaturalGas', dsgn_sup_wtr_temp: 160.0, dsgn_sup_wtr_temp_delt: 30.0)
    assert_model_parity(legacy, composed)
    assert_in_delta(OpenStudio.convert(160.0, 'F', 'C').get, composed.getPlantLoopByName('Hot Water Loop').get.sizingPlant.designLoopExitTemperature, 0.01)
  end

  def test_hw_loop_district_heating_parity
    legacy, composed = build_pair('DistrictHeatingWater')
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getDistrictHeatingWaters.size)
  end

  def test_hw_loop_ambient_heat_pump_parity
    legacy, composed = build_pair('HeatPump')
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getHeatPumpWaterToWaterEquationFitHeatings.size)
    hp = composed.getHeatPumpWaterToWaterEquationFitHeatings.first
    assert_equal('Hot Water Loop Water to Water Heat Pump', hp.name.get)
    # the heat pump's source side is on the ambient loop demand side
    assert(hp.plantLoop.is_initialized && hp.plantLoop.get.name.get == 'Hot Water Loop')
    assert(hp.secondaryPlantLoop.is_initialized, 'heat pump source side connects to the ambient loop')
  end

  def test_hw_loop_air_source_heat_pump_parity
    legacy, composed = build_pair('AirSourceHeatPump')
    assert_model_parity(legacy, composed)
    # the central air source heat pump is modeled as a PlantComponentUserDefined proxy on the loop
    proxies = composed.getPlantComponentUserDefineds
    assert_equal(1, proxies.size)
    assert(proxies.first.plantLoop.is_initialized)
  end

  # The heat pump's EMS setpoint sensor takes its key from the loop's scheduled setpoint manager,
  # which must therefore already be on the supply outlet node when the component is built. An empty
  # key is accepted by the model and by a name/count parity diff, but is an EnergyPlus fatal
  # ("Unique Key Name not found"), so assert the key directly in both models.
  def test_hw_loop_air_source_heat_pump_ems_sensor_key
    legacy, composed = build_pair('AirSourceHeatPump')
    [legacy, composed].each do |model|
      sensor = model.getEnergyManagementSystemSensors.find { |s| s.name.get.include?('Setpt_Mgr_Temp_Sen') }
      refute_nil(sensor, 'the setpoint temperature sensor should exist')
      assert_equal('Hot Water Loop Temp - 180F', sensor.keyName)
    end
  end

  def test_hw_loop_boiler_numeric_checklist
    _legacy, composed = build_pair('NaturalGas')
    boiler = composed.getBoilerHotWaters.first
    assert_in_delta(0.78, boiler.nominalThermalEfficiency, 0.001)
    assert_equal('LeavingSetpointModulated', boiler.boilerFlowMode)
    assert_in_delta(95.0, boiler.waterOutletUpperTemperatureLimit, 0.01)
    assert_in_delta(1.2, boiler.maximumPartLoadRatio, 0.001)
    assert_equal('LeavingBoiler', boiler.efficiencyCurveTemperatureEvaluationVariable.get)
  end

  def test_hw_loop_returns_named_loop
    model = OpenStudio::Model::Model.new
    loop = @composers.hw_loop(model, 'NaturalGas', system_name: 'My HW Loop')
    assert(loop.to_PlantLoop.is_initialized)
    assert_equal('My HW Loop', loop.name.get)
  end

  # ---- chilled water loop ----

  def build_chw_pair(with_condenser: false, **kwargs)
    legacy = OpenStudio::Model::Model.new
    composed = OpenStudio::Model::Model.new
    legacy_cond = composed_cond = nil
    if with_condenser
      legacy_cond = OpenStudio::Model::PlantLoop.new(legacy)
      legacy_cond.setName('Condenser Water Loop')
      composed_cond = OpenStudio::Model::PlantLoop.new(composed)
      composed_cond.setName('Condenser Water Loop')
    end
    legacy_hvac.model_add_chw_loop(legacy, condenser_water_loop: legacy_cond, **kwargs)
    @composers.chw_loop(composed, condenser_water_loop: composed_cond, **kwargs)
    [legacy, composed]
  end

  def test_chw_loop_constant_primary_air_cooled_parity
    legacy, composed = build_chw_pair(chw_pumping_configuration: 'constant primary', chiller_cooling_type: 'AirCooled')
    assert_model_parity(legacy, composed)
    assert_equal('AirCooled', composed.getChillerElectricEIRs.first.condenserType)
  end

  def test_chw_loop_outdoor_air_reset_parity
    legacy, composed = build_chw_pair(chw_pumping_configuration: 'constant primary', chiller_cooling_type: 'AirCooled', outdoor_air_reset: true)
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getSetpointManagerOutdoorAirResets.size)
  end

  def test_chw_loop_district_cooling_parity
    legacy, composed = build_chw_pair(chw_pumping_configuration: 'constant primary', cooling_fuel: 'DistrictCooling')
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getDistrictCoolings.size)
  end

  def test_chw_loop_multiple_chillers_parity
    legacy, composed = build_chw_pair(chw_pumping_configuration: 'constant primary', chiller_cooling_type: 'AirCooled', num_chillers: 2)
    assert_model_parity(legacy, composed)
    assert_equal(2, composed.getChillerElectricEIRs.size)
    composed.getChillerElectricEIRs.each { |chiller| assert_in_delta(0.5, chiller.sizingFactor, 0.001) }
  end

  def test_chw_loop_common_pipe_parity
    legacy, composed = build_chw_pair(chw_pumping_configuration: 'constant primary variable secondary common pipe', chiller_cooling_type: 'AirCooled')
    assert_model_parity(legacy, composed)
    loop = composed.getPlantLoopByName('Chilled Water Loop').get
    assert_equal('CommonPipe', loop.commonPipeSimulation)
    assert_equal(1, composed.getPumpConstantSpeeds.size)
    assert_equal(1, composed.getPumpVariableSpeeds.size)
  end

  def test_chw_loop_water_cooled_economizer_parity
    legacy, composed = build_chw_pair(with_condenser: true, chw_pumping_configuration: 'constant primary',
                                      chiller_cooling_type: 'WaterCooled', waterside_economizer: 'integrated')
    assert_model_parity(legacy, composed)
    assert_equal('WaterCooled', composed.getChillerElectricEIRs.first.condenserType)
    assert_equal(1, composed.getHeatExchangerFluidToFluids.size)
  end

  def test_chw_loop_chiller_numeric_checklist
    _legacy, composed = build_chw_pair(chw_pumping_configuration: 'constant primary', chiller_cooling_type: 'AirCooled')
    chiller = composed.getChillerElectricEIRs.first
    assert_in_delta(OpenStudio.convert(36.0, 'F', 'C').get, chiller.leavingChilledWaterLowerTemperatureLimit, 0.01)
    assert_in_delta(0.15, chiller.minimumPartLoadRatio, 0.001)
    assert_in_delta(0.25, chiller.minimumUnloadingRatio, 0.001)
    assert_equal('ConstantFlow', chiller.chillerFlowMode)
    assert_in_delta(OpenstudioStandards::HVAC.kw_per_ton_to_cop(1.188), chiller.referenceCOP, 0.01)
  end

  # The PRM baseline's system 7/8 chilled water plant: the loop the caller names becomes the
  # secondary (it keeps the plain name and the coils), and the chillers move to a renamed primary
  # joined through a fluid-to-fluid heat exchanger.
  def test_chw_loop_heat_exchanger_config_parity
    legacy, composed = build_chw_pair(with_condenser: true,
                                      chw_pumping_configuration: 'constant primary variable secondary heat exchanger',
                                      chiller_cooling_type: 'WaterCooled', chiller_compressor_type: 'Rotary Screw',
                                      outdoor_air_reset: true)
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getHeatExchangerFluidToFluids.size)
  end

  def test_chw_loop_heat_exchanger_config_returns_primary
    model = OpenStudio::Model::Model.new
    cw = @hvac.model_add_cw_loop(model, use_90_1_design_sizing: false)
    loop = @composers.chw_loop(model, chw_pumping_configuration: 'constant primary variable secondary heat exchanger',
                                      chiller_cooling_type: 'WaterCooled', condenser_water_loop: cw,
                                      outdoor_air_reset: true)
    assert_equal('Chilled Water Loop_Primary', loop.name.get)
    assert(loop.additionalProperties.hasFeature('is_primary_loop'))
    assert_equal('Chilled Water Loop', loop.additionalProperties.getFeatureAsString('secondary_loop_name').get)
    secondary = model.getPlantLoopByName('Chilled Water Loop').get
    assert(secondary.additionalProperties.hasFeature('is_secondary_loop'))
  end

  # This configuration is reached only through the PRM baseline, which test_add_hvac_systems does
  # not exercise, so translate the composed model here to catch a structurally invalid plant.
  def test_chw_loop_heat_exchanger_config_forward_translates
    _legacy, composed = build_chw_pair(with_condenser: true,
                                       chw_pumping_configuration: 'constant primary variable secondary heat exchanger',
                                       chiller_cooling_type: 'WaterCooled', chiller_compressor_type: 'Rotary Screw',
                                       outdoor_air_reset: true)
    ft = OpenStudio::EnergyPlus::ForwardTranslator.new
    ft.translateModel(composed)
    assert_equal(0, ft.errors.size, ft.errors.map(&:logMessage).join("\n"))
  end

  # The primary pump's head is shared across the chillers.
  def test_chw_loop_heat_exchanger_config_multiple_chillers_parity
    legacy, composed = build_chw_pair(with_condenser: true, num_chillers: 2,
                                      chw_pumping_configuration: 'constant primary variable secondary heat exchanger',
                                      chiller_cooling_type: 'WaterCooled', chiller_compressor_type: 'Rotary Screw',
                                      outdoor_air_reset: true)
    assert_model_parity(legacy, composed)
    pump = composed.getPumpVariableSpeeds.find { |p| p.name.get.include?('Primary Pump') }
    assert_in_delta(OpenStudio.convert(7.5, 'ftH_{2}O', 'Pa').get, pump.ratedPumpHead, 1.0)
  end

  # ---- condenser water loop ----

  def build_cw_pair(**kwargs)
    legacy = OpenStudio::Model::Model.new
    composed = OpenStudio::Model::Model.new
    legacy_hvac.model_add_cw_loop(legacy, use_90_1_design_sizing: false, **kwargs)
    @composers.cw_loop(composed, use_90_1_design_sizing: false, **kwargs)
    [legacy, composed]
  end

  def test_cw_loop_twospeed_constant_parity
    legacy, composed = build_cw_pair(pump_spd_ctrl: 'Constant', cooling_tower_capacity_control: 'TwoSpeed Fan')
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getCoolingTowerTwoSpeeds.size)
    assert_equal(1, composed.getPumpConstantSpeeds.size)
  end

  def test_cw_loop_variable_pump_parity
    legacy, composed = build_cw_pair(pump_spd_ctrl: 'Variable', cooling_tower_capacity_control: 'TwoSpeed Fan')
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getPumpVariableSpeeds.size)
  end

  def test_cw_loop_headered_variable_pump_parity
    legacy, composed = build_cw_pair(pump_spd_ctrl: 'HeaderedVariable', cooling_tower_capacity_control: 'TwoSpeed Fan')
    assert_model_parity(legacy, composed)
    pumps = composed.getHeaderedPumpsVariableSpeeds
    assert_equal(1, pumps.size)
    assert_equal(2, pumps.first.numberofPumpsinBank)
  end

  def test_cw_loop_single_speed_fluid_bypass_parity
    legacy, composed = build_cw_pair(pump_spd_ctrl: 'Constant', cooling_tower_capacity_control: 'Fluid Bypass')
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getCoolingTowerSingleSpeeds.size)
    # The legacy setCellControl('FluidBypass') is a no-op (an invalid CellControl enum value, which
    # only accepts MinimalCell/MaximalCell); the composer reproduces the same ignored call.
    assert_equal(legacy.getCoolingTowerSingleSpeeds.first.cellControl, composed.getCoolingTowerSingleSpeeds.first.cellControl)
  end

  def test_cw_loop_single_speed_fan_cycling_parity
    legacy, composed = build_cw_pair(pump_spd_ctrl: 'Constant', cooling_tower_capacity_control: 'Fan Cycling')
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getCoolingTowerSingleSpeeds.size)
    assert_equal(legacy.getCoolingTowerSingleSpeeds.first.cellControl, composed.getCoolingTowerSingleSpeeds.first.cellControl)
  end

  def test_cw_loop_setpoint_manager_checklist
    _legacy, composed = build_cw_pair(pump_spd_ctrl: 'Constant', cooling_tower_capacity_control: 'TwoSpeed Fan')
    spm = composed.getSetpointManagerFollowOutdoorAirTemperatures.first
    assert_equal('OutdoorAirWetBulb', spm.referenceTemperatureType)
    assert_in_delta(OpenStudio.convert(85.0, 'F', 'C').get, spm.maximumSetpointTemperature, 0.01)
    assert_in_delta(OpenStudio.convert(70.0, 'F', 'C').get, spm.minimumSetpointTemperature, 0.01)
    assert_in_delta(OpenStudio.convert(7.0, 'R', 'K').get, spm.offsetTemperatureDifference, 0.01)
  end

  def test_cw_loop_sizing_plant_coincident_fields
    _legacy, composed = build_cw_pair(pump_spd_ctrl: 'Constant', cooling_tower_capacity_control: 'TwoSpeed Fan')
    sizing = composed.getPlantLoopByName('Condenser Water Loop').get.sizingPlant
    assert_equal('Coincident', sizing.sizingOption)
    assert_equal(6, sizing.zoneTimestepsinAveragingWindow)
    assert_equal('GlobalCoolingSizingFactor', sizing.coincidentSizingFactorMode)
  end

  # use_90_1_design_sizing defaults to true and no caller overrides it, so this is the path every
  # condenser loop in the library actually takes. The sizing runs as an imperative tail because it
  # reads the model's design days.
  def build_cw_pair_90_1(**kwargs)
    legacy = OpenStudio::Model::Model.new
    composed = OpenStudio::Model::Model.new
    legacy_hvac.model_add_cw_loop(legacy, **kwargs)
    @composers.cw_loop(composed, **kwargs)
    [legacy, composed]
  end

  def test_cw_loop_90_1_design_sizing_parity_no_design_days
    legacy, composed = build_cw_pair_90_1
    assert_model_parity(legacy, composed)
    # With no design days in the model the CTI 78 F rating condition is used.
    spm = composed.getSetpointManagerFollowOutdoorAirTemperatures.first
    assert_equal('Condenser Water Loop Setpoint Manager Follow OATwb with 7.0F Approach', spm.name.get)
    assert_in_delta(OpenStudio.convert(85.0, 'F', 'C').get, composed.getPlantLoops.first.sizingPlant.designLoopExitTemperature, 1e-6)
  end

  def test_cw_loop_90_1_design_sizing_parity_variable_speed_tower
    legacy, composed = build_cw_pair_90_1(cooling_tower_capacity_control: 'Variable Speed Fan')
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getCoolingTowerVariableSpeeds.size)
  end

  # Every standard's model_cw_loop_cooling_tower_fan_type returns 'Variable Speed Fan', so this is
  # the tower every PRM baseline condenser loop builds.
  def test_cw_loop_variable_speed_tower_parity
    legacy, composed = build_cw_pair(cooling_tower_capacity_control: 'Variable Speed Fan')
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getCoolingTowerVariableSpeeds.size)
  end

  def test_cw_loop_variable_speed_tower_checklist
    _legacy, composed = build_cw_pair(cooling_tower_capacity_control: 'Variable Speed Fan')
    tower = composed.getCoolingTowerVariableSpeeds.first
    assert_in_delta(OpenStudio.convert(10.0, 'R', 'K').get, tower.designRangeTemperature.get, 1e-6)
    assert_in_delta(OpenStudio.convert(7.0, 'R', 'K').get, tower.designApproachTemperature.get, 1e-6)
    assert_in_delta(0.125, tower.fractionofTowerCapacityinFreeConvectionRegime.get, 1e-9)
    curve = tower.fanPowerRatioFunctionofAirFlowRateRatioCurve.get.to_CurveCubic.get
    assert_equal('VSD-TWR-FAN-FPLR', curve.name.get)
    assert_in_delta(0.33162901, curve.coefficient1Constant, 1e-9)
    assert_in_delta(0.9484823, curve.coefficient4xPOW3, 1e-9)
  end

  # ---- heat pump loop ----

  def build_hp_pair(**kwargs)
    legacy = OpenStudio::Model::Model.new
    composed = OpenStudio::Model::Model.new
    legacy_hvac.model_add_hp_loop(legacy, **kwargs)
    @composers.hp_loop(composed, **kwargs)
    [legacy, composed]
  end

  def test_hp_loop_default_evap_gas_parity
    legacy, composed = build_hp_pair
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getEvaporativeFluidCoolerSingleSpeeds.size)
    assert_equal(1, composed.getBoilerHotWaters.size)
  end

  def test_hp_loop_cooling_tower_parity
    legacy, composed = build_hp_pair(cooling_type: 'CoolingTower')
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getCoolingTowerTwoSpeeds.size)
  end

  def test_hp_loop_district_parity
    legacy, composed = build_hp_pair(cooling_fuel: 'DistrictCooling', heating_fuel: 'DistrictHeatingWater')
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getDistrictCoolings.size)
    assert_equal(1, composed.getDistrictHeatingWaters.size)
  end

  def test_hp_loop_evap_two_speed_parity
    legacy, composed = build_hp_pair(cooling_type: 'EvaporativeFluidCoolerTwoSpeed')
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getEvaporativeFluidCoolerTwoSpeeds.size)
  end

  def test_hp_loop_dual_setpoint_managers_share_two_schedules
    _legacy, composed = build_hp_pair
    loop = composed.getPlantLoopByName('Heat Pump Loop').get
    assert_equal('SequentialLoad', loop.loadDistributionScheme)
    assert_in_delta(10.0, loop.minimumLoopTemperature, 0.01)
    assert_in_delta(35.0, loop.maximumLoopTemperature, 0.01)
    managers = composed.getSetpointManagerScheduledDualSetpoints
    assert_equal(3, managers.size, 'loop, cooling-outlet, and heating-outlet dual setpoint managers')
    schedules = managers.flat_map { |m| [m.highSetpointSchedule, m.lowSetpointSchedule] }.select(&:is_initialized).map { |s| s.get.name.get }.uniq
    assert_equal(2, schedules.size, 'all three managers share the same high and low temperature schedules')
  end

  def test_hp_loop_air_source_heat_pump_parity
    legacy, composed = build_hp_pair(heating_fuel: 'AirSourceHeatPump')
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getPlantComponentUserDefineds.size)
  end

  # Reproduced legacy behavior, not an endorsement: the heat pump's EMS setpoint sensor looks for a
  # SetpointManagerScheduled, but this loop carries dual-setpoint managers, so the key is empty in
  # both models. A model built this way is an EnergyPlus fatal; the corresponding CI case is
  # commented out in test_add_hvac_systems.rb.
  def test_hp_loop_air_source_heat_pump_reproduces_empty_sensor_key
    legacy, composed = build_hp_pair(heating_fuel: 'AirSourceHeatPump')
    [legacy, composed].each do |model|
      sensor = model.getEnergyManagementSystemSensors.find { |s| s.name.get.include?('Setpt_Mgr_Temp_Sen') }
      refute_nil(sensor)
      assert_equal('', sensor.keyName)
    end
  end

  def test_hp_loop_variable_speed_tower_parity
    legacy, composed = build_hp_pair(cooling_type: 'CoolingTowerVariableSpeed')
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getCoolingTowerVariableSpeeds.size)
  end

  def test_hp_loop_dry_fluid_cooler_parity
    legacy, composed = build_hp_pair(cooling_type: 'FluidCooler')
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getFluidCoolerSingleSpeeds.size)
  end

  def test_hp_loop_dry_fluid_cooler_two_speed_parity
    legacy, composed = build_hp_pair(cooling_type: 'FluidCoolerTwoSpeed')
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getFluidCoolerTwoSpeeds.size)
  end

  # The legacy method replaces the constructor's hard-coded design flows with autosized ones.
  def test_hp_loop_dry_fluid_cooler_autosizes_flows
    _legacy, composed = build_hp_pair(cooling_type: 'FluidCooler')
    cooler = composed.getFluidCoolerSingleSpeeds.first
    assert_equal('UFactorTimesAreaAndDesignWaterFlowRate', cooler.performanceInputMethod)
    assert(cooler.isDesignWaterFlowRateAutosized)
    assert(cooler.isDesignAirFlowRateAutosized)
  end

  # ---- PSZ-AC (air-system family) ----

  # Build a model with n simple thermal zones (each with a space).
  def model_with_zones(count)
    model = OpenStudio::Model::Model.new
    zones = Array.new(count) do |i|
      zone = OpenStudio::Model::ThermalZone.new(model)
      zone.setName("Zone #{i + 1}")
      OpenStudio::Model::Space.new(model).setThermalZone(zone)
      zone
    end
    [model, zones]
  end

  def build_psz_pair(zone_count: 1, **kwargs)
    legacy, legacy_zones = model_with_zones(zone_count)
    composed, composed_zones = model_with_zones(zone_count)
    legacy_hvac.model_add_psz_ac(legacy, legacy_zones, **kwargs)
    @composers.psz_ac(composed, composed_zones, **kwargs)
    [legacy, composed]
  end

  def test_psz_ac_default_parity
    legacy, composed = build_psz_pair
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getAirLoopHVACs.size)
    assert_equal(1, composed.getAirLoopHVACUnitarySystems.size)
    assert_equal(1, composed.getCoilCoolingDXSingleSpeeds.size)
  end

  def test_psz_ac_gas_heat_electric_backup_parity
    legacy, composed = build_psz_pair(heating_type: 'NaturalGas', supplemental_heating_type: 'Electricity')
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getCoilHeatingGass.size)
  end

  def test_psz_ac_electric_heat_parity
    legacy, composed = build_psz_pair(heating_type: 'Electricity')
    assert_model_parity(legacy, composed)
  end

  def test_psz_ac_cycling_fan_parity
    legacy, composed = build_psz_pair(fan_type: 'Cycling')
    assert_model_parity(legacy, composed)
  end

  def test_psz_ac_blow_through_parity
    legacy, composed = build_psz_pair(fan_location: 'BlowThrough')
    assert_model_parity(legacy, composed)
    assert_equal('BlowThrough', composed.getAirLoopHVACUnitarySystems.first.fanPlacement.get)
  end

  def test_psz_ac_multiple_zones_parity
    legacy, composed = build_psz_pair(zone_count: 3)
    assert_model_parity(legacy, composed)
    assert_equal(3, composed.getAirLoopHVACs.size)
  end

  def test_psz_ac_checklist
    _legacy, composed = build_psz_pair
    air_loop = composed.getAirLoopHVACs.first
    assert_equal('Zone 1 PSZ-AC', air_loop.name.get)
    assert_equal('CycleOnAny', air_loop.nightCycleControlType)
    spm = composed.getSetpointManagerSingleZoneReheats.first
    assert_equal('Zone 1 Setpoint Manager SZ Reheat', spm.name.get)
    assert_in_delta(OpenStudio.convert(122.0, 'F', 'C').get, spm.maximumSupplyAirTemperature, 0.01)
    # standard sizing applied via the shared helper
    assert_in_delta(0.008, air_loop.sizingSystem.preheatDesignHumidityRatio, 1e-6)
    assert_equal('ZoneSum', air_loop.sizingSystem.systemOutdoorAirMethod)
  end

  def test_psz_ac_forward_translates
    _legacy, composed = build_psz_pair
    ft = OpenStudio::EnergyPlus::ForwardTranslator.new
    ft.translateModel(composed)
    assert_equal(0, ft.errors.size, ft.errors.map(&:logMessage).join("\n"))
  end

  def test_psz_ac_water_coils_parity
    legacy, legacy_zones = model_with_zones(1)
    composed, composed_zones = model_with_zones(1)
    legacy_hw = add_water_loop(legacy, 'HW', 82.2, 11.1)
    legacy_chw = add_water_loop(legacy, 'CHW', 6.7, 6.7)
    composed_hw = add_water_loop(composed, 'HW', 82.2, 11.1)
    composed_chw = add_water_loop(composed, 'CHW', 6.7, 6.7)
    legacy_hvac.model_add_psz_ac(legacy, legacy_zones, cooling_type: 'Water', heating_type: 'Water', hot_water_loop: legacy_hw, chilled_water_loop: legacy_chw)
    @composers.psz_ac(composed, composed_zones, cooling_type: 'Water', heating_type: 'Water', hot_water_loop: composed_hw, chilled_water_loop: composed_chw)
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getCoilCoolingWaters.size)
    assert_equal(1, composed.getCoilHeatingWaters.size)
  end

  # PSZ-HP: the dispatcher's heat-pump packaged system, reached by create_typical, the hvac
  # inference data of all three standards, and the PRM baseline.
  def test_psz_ac_single_speed_heat_pump_parity
    legacy, composed = build_psz_pair(cooling_type: 'Single Speed Heat Pump',
                                      heating_type: 'Single Speed Heat Pump',
                                      supplemental_heating_type: 'Electricity')
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getCoilHeatingDXSingleSpeeds.size)
    assert_equal(1, composed.getCoilCoolingDXSingleSpeeds.size)
  end

  # EnergyPlus rejects a unitary system whose controlling zone is blank ("Controlling Zone or
  # Thermostat Location cannot be blank when Control Type = Load"), and a name-and-count parity diff
  # does not compare the field, so assert it directly in both models.
  def test_psz_ac_unitary_controlling_zone
    legacy, composed = build_psz_pair
    [legacy, composed].each do |model|
      unitary = model.getAirLoopHVACUnitarySystems.first
      assert(unitary.controllingZoneorThermostatLocation.is_initialized, 'controlling zone must be set')
      assert_equal('Zone 1', unitary.controllingZoneorThermostatLocation.get.name.get)
    end
  end

  def test_psz_ac_heat_pump_checklist
    _legacy, composed = build_psz_pair(cooling_type: 'Single Speed Heat Pump',
                                       heating_type: 'Single Speed Heat Pump',
                                       supplemental_heating_type: 'Electricity')
    unitary = composed.getAirLoopHVACUnitarySystems.first
    assert_equal('Zone 1 PSZ-AC Unitary HP', unitary.name.get)
    assert_in_delta(OpenStudio.convert(40.0, 'F', 'C').get,
                    unitary.maximumOutdoorDryBulbTemperatureforSupplementalHeaterOperation, 1e-6)
    coil = composed.getCoilHeatingDXSingleSpeeds.first
    assert_equal('Zone 1 HP Htg Coil', coil.name.get)
    assert_in_delta(3.3, coil.ratedCOP, 1e-9)
  end

  def test_psz_ac_water_to_air_heat_pump_parity
    legacy, legacy_zones = model_with_zones(1)
    composed, composed_zones = model_with_zones(1)
    [[legacy, legacy_zones, true], [composed, composed_zones, false]].each do |model, zones, is_legacy|
      builder = is_legacy ? legacy_hvac : @hvac
      hw = builder.model_add_hw_loop(model, 'NaturalGas')
      chw = builder.model_add_chw_loop(model, chw_pumping_configuration: 'constant primary', chiller_cooling_type: 'AirCooled')
      args = { cooling_type: 'Water To Air Heat Pump', heating_type: 'Water To Air Heat Pump',
               supplemental_heating_type: 'Electricity', hot_water_loop: hw, chilled_water_loop: chw }
      if is_legacy
        legacy_hvac.model_add_psz_ac(model, zones, **args)
      else
        @composers.psz_ac(model, zones, **args)
      end
    end
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getCoilHeatingWaterToAirHeatPumpEquationFits.size)
    assert_equal(1, composed.getCoilCoolingWaterToAirHeatPumpEquationFits.size)
  end

  # ---- PSZ-VAV ----

  def build_psz_vav_pair(zone_count: 1, **kwargs)
    legacy, legacy_zones = model_with_zones(zone_count)
    composed, composed_zones = model_with_zones(zone_count)
    legacy_hvac.model_add_psz_vav(legacy, legacy_zones, **kwargs)
    @composers.psz_vav(composed, composed_zones, **kwargs)
    [legacy, composed]
  end

  def test_psz_vav_default_parity
    legacy, composed = build_psz_vav_pair
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getCoilCoolingDXVariableSpeeds.size)
    unitary = composed.getAirLoopHVACUnitarySystems.first
    assert_equal('SingleZoneVAV', unitary.controlType)
    assert_equal('BlowThrough', unitary.fanPlacement.get)
  end

  def test_psz_vav_gas_heat_electric_backup_parity
    legacy, composed = build_psz_vav_pair(heating_type: 'NaturalGas', supplemental_heating_type: 'Electricity')
    assert_model_parity(legacy, composed)
  end

  def test_psz_vav_electric_heat_parity
    legacy, composed = build_psz_vav_pair(heating_type: 'Electricity')
    assert_model_parity(legacy, composed)
  end

  def test_psz_vav_multiple_zones_parity
    legacy, composed = build_psz_vav_pair(zone_count: 2)
    assert_model_parity(legacy, composed)
    assert_equal(2, composed.getAirLoopHVACs.size)
  end

  def test_psz_vav_checklist
    _legacy, composed = build_psz_vav_pair
    coil = composed.getCoilCoolingDXVariableSpeeds.first
    assert_in_delta(10.0, coil.basinHeaterCapacity, 0.01)
    assert_equal(1, coil.speeds.size)
    controller = composed.getControllerOutdoorAirs.first
    assert_equal('Zone 1 PSZ-VAV OA Sys Controller', controller.name.get)
    assert_equal('BypassWhenOAFlowGreaterThanMinimum', controller.getHeatRecoveryBypassControlType.get)
    fan = composed.getFanVariableVolumes.first
    assert_equal('VAV System Fans', fan.endUseSubcategory)
  end

  def test_psz_vav_forward_translates
    _legacy, composed = build_psz_vav_pair
    ft = OpenStudio::EnergyPlus::ForwardTranslator.new
    ft.translateModel(composed)
    assert_equal(0, ft.errors.size, ft.errors.map(&:logMessage).join("\n"))
  end

  def test_psz_vav_water_coils_parity
    legacy, legacy_zones = model_with_zones(1)
    composed, composed_zones = model_with_zones(1)
    legacy_hw = add_water_loop(legacy, 'HW', 82.2, 11.1)
    legacy_chw = add_water_loop(legacy, 'CHW', 6.7, 6.7)
    composed_hw = add_water_loop(composed, 'HW', 82.2, 11.1)
    composed_chw = add_water_loop(composed, 'CHW', 6.7, 6.7)
    legacy_hvac.model_add_psz_vav(legacy, legacy_zones, cooling_type: 'WaterCooled', heating_type: 'Water', hot_water_loop: legacy_hw, chilled_water_loop: legacy_chw)
    @composers.psz_vav(composed, composed_zones, cooling_type: 'WaterCooled', heating_type: 'Water', hot_water_loop: composed_hw, chilled_water_loop: composed_chw)
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getCoilCoolingWaters.size)
    assert_equal(1, composed.getCoilHeatingWaters.size)
  end

  # ---- VAV reheat (multi-zone) ----

  def build_vav_pair(zone_count: 2, **kwargs)
    legacy, legacy_zones = model_with_zones(zone_count)
    composed, composed_zones = model_with_zones(zone_count)
    legacy_hvac.model_add_vav_reheat(legacy, legacy_zones, **kwargs)
    @composers.vav_reheat(composed, composed_zones, **kwargs)
    [legacy, composed]
  end

  # Build a pair of models where the last zone is the return plenum for the rest — the shape the
  # LargeOffice / MediumOffice hvac maps use.
  def build_plenum_pair(zone_count: 2, &block)
    legacy, legacy_zones = model_with_zones(zone_count + 1)
    composed, composed_zones = model_with_zones(zone_count + 1)
    block.call(legacy, legacy_zones[0...-1], legacy_zones.last, true)
    block.call(composed, composed_zones[0...-1], composed_zones.last, false)
    [legacy, composed]
  end

  def test_vav_reheat_return_plenum_parity
    legacy, composed = build_plenum_pair do |model, zones, plenum, is_legacy|
      if is_legacy
        legacy_hvac.model_add_vav_reheat(model, zones, return_plenum: plenum)
      else
        @composers.vav_reheat(model, zones, return_plenum: plenum)
      end
    end
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getAirLoopHVACReturnPlenums.size)
    assert_equal('Zone 3', composed.getAirLoopHVACReturnPlenums.first.thermalZone.get.name.get)
  end

  def test_pvav_return_plenum_parity
    legacy, composed = build_plenum_pair do |model, zones, plenum, is_legacy|
      if is_legacy
        legacy_hvac.model_add_pvav(model, zones, return_plenum: plenum)
      else
        @composers.pvav(model, zones, return_plenum: plenum)
      end
    end
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getAirLoopHVACReturnPlenums.size)
  end

  def test_vav_reheat_default_parity
    legacy, composed = build_vav_pair
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getAirLoopHVACs.size, 'one shared air loop serves all zones')
    assert_equal(1, composed.getCoilCoolingDXTwoSpeeds.size)
    assert_equal(2, composed.getAirTerminalSingleDuctVAVNoReheats.size)
  end

  def test_vav_reheat_gas_reheat_parity
    legacy, composed = build_vav_pair(reheat_type: 'NaturalGas')
    assert_model_parity(legacy, composed)
    assert_equal(2, composed.getAirTerminalSingleDuctVAVReheats.size)
  end

  def test_vav_reheat_electric_parity
    legacy, composed = build_vav_pair(heating_type: 'Electricity', reheat_type: 'Electricity')
    assert_model_parity(legacy, composed)
  end

  def test_vav_reheat_three_zones_parity
    legacy, composed = build_vav_pair(zone_count: 3, reheat_type: 'NaturalGas')
    assert_model_parity(legacy, composed)
    assert_equal(3, composed.getAirTerminalSingleDuctVAVReheats.size)
  end

  def test_vav_reheat_checklist
    _legacy, composed = build_vav_pair(reheat_type: 'NaturalGas')
    air_loop = composed.getAirLoopHVACs.first
    assert_equal('2 Zone VAV', air_loop.name.get)
    fan = composed.getFanVariableVolumes.first
    assert_in_delta(0.62, fan.fanEfficiency, 0.001)
    controller = composed.getControllerOutdoorAirs.first
    assert_equal('FixedMinimum', controller.getMinimumLimitType)
    assert_equal('ZoneSum', controller.controllerMechanicalVentilation.systemOutdoorAirMethod)
    terminal = composed.getAirTerminalSingleDuctVAVReheats.first
    assert_equal('Normal', terminal.damperHeatingAction)
    assert_in_delta(0.3, terminal.constantMinimumAirFlowFraction.get, 0.001)
    assert_in_delta(OpenStudio.convert(104.0, 'F', 'C').get, terminal.maximumReheatAirTemperature, 0.01)
  end

  def test_vav_reheat_forward_translates
    _legacy, composed = build_vav_pair(reheat_type: 'NaturalGas')
    ft = OpenStudio::EnergyPlus::ForwardTranslator.new
    ft.translateModel(composed)
    assert_equal(0, ft.errors.size, ft.errors.map(&:logMessage).join("\n"))
  end

  # Add a bare hot/chilled water loop with fixed sizing to a model (for water-coil parity tests).
  def add_water_loop(model, name, exit_c, delta_k)
    loop = OpenStudio::Model::PlantLoop.new(model)
    loop.setName(name)
    loop.sizingPlant.setDesignLoopExitTemperature(exit_c)
    loop.sizingPlant.setLoopDesignTemperatureDifference(delta_k)
    loop
  end

  def build_vav_water_pair(**kwargs)
    legacy, legacy_zones = model_with_zones(2)
    composed, composed_zones = model_with_zones(2)
    legacy_loops = [add_water_loop(legacy, 'HW', 82.2, 11.1), add_water_loop(legacy, 'CHW', 6.7, 6.7)]
    composed_loops = [add_water_loop(composed, 'HW', 82.2, 11.1), add_water_loop(composed, 'CHW', 6.7, 6.7)]
    legacy_hvac.model_add_vav_reheat(legacy, legacy_zones, hot_water_loop: legacy_loops[0], chilled_water_loop: legacy_loops[1], **kwargs)
    @composers.vav_reheat(composed, composed_zones, hot_water_loop: composed_loops[0], chilled_water_loop: composed_loops[1], **kwargs)
    [legacy, composed]
  end

  def test_vav_reheat_water_coils_parity
    legacy, composed = build_vav_water_pair(reheat_type: 'Water')
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getCoilCoolingWaters.size)
    assert_equal(3, composed.getCoilHeatingWaters.size, 'one main coil plus one reheat coil per zone')
  end

  def test_vav_reheat_water_coil_checklist
    _legacy, composed = build_vav_water_pair(reheat_type: 'Water')
    main = composed.getCoilHeatingWaters.find { |c| c.name.get.include?('Main') }
    assert_in_delta(82.2, main.ratedInletWaterTemperature, 0.05)
    assert_in_delta(71.1, main.ratedOutletWaterTemperature, 0.05)
    assert_equal("#{main.name.get} Controller", main.controllerWaterCoil.get.name.get)
    assert_in_delta(0.1, main.controllerWaterCoil.get.controllerConvergenceTolerance.get, 1e-6)
    clg = composed.getCoilCoolingWaters.first
    assert_equal('CrossFlow', clg.heatExchangerConfiguration)
    assert_equal('Reverse', clg.controllerWaterCoil.get.action.get)
  end

  def test_vav_reheat_water_main_gas_reheat_parity
    legacy, composed = build_vav_water_pair(reheat_type: 'NaturalGas')
    assert_model_parity(legacy, composed)
  end

  # ---- PVAV (packaged multi-zone VAV) ----

  def test_pvav_default_parity
    legacy, legacy_zones = model_with_zones(2)
    composed, composed_zones = model_with_zones(2)
    legacy_hvac.model_add_pvav(legacy, legacy_zones)
    @composers.pvav(composed, composed_zones)
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getAirLoopHVACs.size)
    assert_equal('2 Zone PVAV', composed.getAirLoopHVACs.first.name.get)
    assert_equal(2, composed.getCoilHeatingElectrics.select { |c| c.name.get.include?('Reheat') }.size)
  end

  def test_pvav_water_parity
    legacy, legacy_zones = model_with_zones(2)
    composed, composed_zones = model_with_zones(2)
    lhw = add_water_loop(legacy, 'HW', 82.2, 11.1)
    lchw = add_water_loop(legacy, 'CHW', 6.7, 6.7)
    chw = add_water_loop(composed, 'HW', 82.2, 11.1)
    cchw = add_water_loop(composed, 'CHW', 6.7, 6.7)
    legacy_hvac.model_add_pvav(legacy, legacy_zones, hot_water_loop: lhw, chilled_water_loop: lchw)
    @composers.pvav(composed, composed_zones, hot_water_loop: chw, chilled_water_loop: cchw)
    assert_model_parity(legacy, composed)
    assert_equal(3, composed.getCoilHeatingWaters.size, 'main coil plus one reheat coil per zone')
    assert_equal(1, composed.getCoilCoolingWaters.size)
  end

  def test_pvav_forward_translates
    model, zones = model_with_zones(2)
    @composers.pvav(model, zones)
    ft = OpenStudio::EnergyPlus::ForwardTranslator.new
    ft.translateModel(model)
    assert_equal(0, ft.errors.size, ft.errors.map(&:logMessage).join("\n"))
  end

  # ---- CAV (constant air volume) ----

  def build_cav_pair(chilled: false, **kwargs)
    legacy, legacy_zones = model_with_zones(2)
    composed, composed_zones = model_with_zones(2)
    legacy_hw = add_water_loop(legacy, 'HW', 82.2, 11.1)
    composed_hw = add_water_loop(composed, 'HW', 82.2, 11.1)
    extra_legacy = {}
    extra_composed = {}
    if chilled
      extra_legacy[:chilled_water_loop] = add_water_loop(legacy, 'CHW', 6.7, 6.7)
      extra_composed[:chilled_water_loop] = add_water_loop(composed, 'CHW', 6.7, 6.7)
    end
    legacy_hvac.model_add_cav(legacy, legacy_zones, hot_water_loop: legacy_hw, **extra_legacy, **kwargs)
    @composers.cav(composed, composed_zones, hot_water_loop: composed_hw, **extra_composed, **kwargs)
    [legacy, composed]
  end

  def test_cav_dx_cooling_parity
    legacy, composed = build_cav_pair
    assert_model_parity(legacy, composed)
    assert_equal('2 Zone CAV', composed.getAirLoopHVACs.first.name.get)
    assert_equal(1, composed.getCoilCoolingDXTwoSpeeds.size)
  end

  def test_cav_chilled_water_parity
    legacy, composed = build_cav_pair(chilled: true)
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getCoilCoolingWaters.size)
  end

  def test_cav_checklist
    _legacy, composed = build_cav_pair
    fan = composed.getFanConstantVolumes.first
    assert_equal('CAV System Fans', fan.endUseSubcategory)
    terminal = composed.getAirTerminalSingleDuctVAVReheats.first
    assert_in_delta(0.5, terminal.maximumFlowFractionDuringReheat.get, 0.001)
  end

  def test_cav_requires_hot_water_loop
    model, zones = model_with_zones(1)
    assert_raises(ArgumentError) { @composers.cav(model, zones) }
  end

  # ---- VAV with parallel fan-powered boxes ----

  def test_vav_pfp_boxes_parity
    legacy, legacy_zones = model_with_zones(2)
    composed, composed_zones = model_with_zones(2)
    legacy_chw = add_water_loop(legacy, 'CHW', 6.7, 6.7)
    composed_chw = add_water_loop(composed, 'CHW', 6.7, 6.7)
    legacy_hvac.model_add_vav_pfp_boxes(legacy, legacy_zones, chilled_water_loop: legacy_chw)
    @composers.vav_pfp_boxes(composed, composed_zones, chilled_water_loop: composed_chw)
    assert_model_parity(legacy, composed)
    assert_equal(2, composed.getAirTerminalSingleDuctParallelPIUReheats.size)
    assert_equal(1, composed.getCoilCoolingWaters.size)
  end

  def test_vav_pfp_boxes_checklist
    model, zones = model_with_zones(1)
    chw = add_water_loop(model, 'CHW', 6.7, 6.7)
    @composers.vav_pfp_boxes(model, zones, chilled_water_loop: chw)
    terminal = model.getAirTerminalSingleDuctParallelPIUReheats.first
    assert_equal('Zone 1 PFP Term', terminal.name.get)
    assert(terminal.fan.to_FanConstantVolume.is_initialized)
    assert(terminal.reheatCoil.to_CoilHeatingElectric.is_initialized)
  end

  def test_vav_pfp_boxes_forward_translates
    model, zones = model_with_zones(2)
    chw = add_water_loop(model, 'CHW', 6.7, 6.7)
    @composers.vav_pfp_boxes(model, zones, chilled_water_loop: chw)
    ft = OpenStudio::EnergyPlus::ForwardTranslator.new
    ft.translateModel(model)
    assert_equal(0, ft.errors.size, ft.errors.map(&:logMessage).join("\n"))
  end

  def test_vav_pfp_boxes_requires_chilled_water_loop
    model, zones = model_with_zones(1)
    assert_raises(ArgumentError) { @composers.vav_pfp_boxes(model, zones) }
  end

  def test_pvav_pfp_boxes_dx_parity
    legacy, legacy_zones = model_with_zones(2)
    composed, composed_zones = model_with_zones(2)
    legacy_hvac.model_add_pvav_pfp_boxes(legacy, legacy_zones)
    @composers.pvav_pfp_boxes(composed, composed_zones)
    assert_model_parity(legacy, composed)
    assert_equal('2 Zone PVAV with PFP Boxes and Reheat', composed.getAirLoopHVACs.first.name.get)
    assert_equal(2, composed.getAirTerminalSingleDuctParallelPIUReheats.size)
    assert_equal(1, composed.getCoilCoolingDXTwoSpeeds.size)
  end

  def test_pvav_pfp_boxes_chilled_water_parity
    legacy, legacy_zones = model_with_zones(2)
    composed, composed_zones = model_with_zones(2)
    legacy_chw = add_water_loop(legacy, 'CHW', 6.7, 6.7)
    composed_chw = add_water_loop(composed, 'CHW', 6.7, 6.7)
    legacy_hvac.model_add_pvav_pfp_boxes(legacy, legacy_zones, chilled_water_loop: legacy_chw)
    @composers.pvav_pfp_boxes(composed, composed_zones, chilled_water_loop: composed_chw)
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getCoilCoolingWaters.size)
  end

  # ---- furnace / central AC (per zone) ----

  def build_furnace_pair(**kwargs)
    legacy, legacy_zones = model_with_zones(2)
    composed, composed_zones = model_with_zones(2)
    legacy_hvac.model_add_furnace_central_ac(legacy, legacy_zones, **kwargs)
    @composers.furnace_central_ac(composed, composed_zones, **kwargs)
    [legacy, composed]
  end

  def test_furnace_heating_only_parity
    legacy, composed = build_furnace_pair
    assert_model_parity(legacy, composed)
    assert_equal(2, composed.getAirLoopHVACs.size)
    assert_equal(2, composed.getCoilHeatingGass.size)
    assert_equal(0, composed.getCoilCoolingDXSingleSpeeds.size)
  end

  def test_furnace_heating_and_cooling_parity
    legacy, composed = build_furnace_pair(cooling: true)
    assert_model_parity(legacy, composed)
    assert_equal(2, composed.getCoilCoolingDXSingleSpeeds.size)
  end

  def test_furnace_cooling_only_with_ventilation_parity
    legacy, composed = build_furnace_pair(heating: false, cooling: true, ventilation: true)
    assert_model_parity(legacy, composed)
    assert_equal(2, composed.getAirLoopHVACOutdoorAirSystems.size)
  end

  def test_furnace_dx_coil_checklist
    _legacy, composed = build_furnace_pair(cooling: true)
    coil = composed.getCoilCoolingDXSingleSpeeds.first
    assert_in_delta(0.73, coil.ratedSensibleHeatRatio.get, 0.001)
    assert_equal('AirCooled', coil.condenserType)
    assert_in_delta(3.0, coil.maximumCyclingRate, 0.001)
    assert_in_delta(45.0, coil.latentCapacityTimeConstant, 0.001)
  end

  def test_furnace_forward_translates
    model, zones = model_with_zones(2)
    @composers.furnace_central_ac(model, zones, cooling: true)
    ft = OpenStudio::EnergyPlus::ForwardTranslator.new
    ft.translateModel(model)
    assert_equal(0, ft.errors.size, ft.errors.map(&:logMessage).join("\n"))
  end

  # ---- DOAS (dedicated outdoor air system) ----

  # Build a model with n thermal zones each carrying a nonzero design outdoor air requirement, so the
  # DOAS is actually added (it skips zones, and the whole system, when the OA requirement is zero).
  def model_with_oa_zones(count)
    model = OpenStudio::Model::Model.new
    zones = Array.new(count) do |i|
      zone = OpenStudio::Model::ThermalZone.new(model)
      zone.setName("Zone #{i + 1}")
      space = OpenStudio::Model::Space.new(model)
      space.setThermalZone(zone)
      dsn_oa = OpenStudio::Model::DesignSpecificationOutdoorAir.new(model)
      dsn_oa.setName("Zone #{i + 1} OA")
      dsn_oa.setOutdoorAirMethod('Sum')
      dsn_oa.setOutdoorAirFlowRate(0.05)
      space.setDesignSpecificationOutdoorAir(dsn_oa)
      zone
    end
    [model, zones]
  end

  def build_doas_pair(zone_count: 2, with_hw: false, with_chw: false, **kwargs)
    legacy, legacy_zones = model_with_oa_zones(zone_count)
    composed, composed_zones = model_with_oa_zones(zone_count)
    legacy_hw = with_hw ? legacy_hvac.model_add_hw_loop(legacy, 'NaturalGas') : nil
    composed_hw = with_hw ? @hvac.model_add_hw_loop(composed, 'NaturalGas') : nil
    legacy_chw = with_chw ? legacy_hvac.model_add_chw_loop(legacy, chw_pumping_configuration: 'constant primary', chiller_cooling_type: 'AirCooled') : nil
    composed_chw = with_chw ? @hvac.model_add_chw_loop(composed, chw_pumping_configuration: 'constant primary', chiller_cooling_type: 'AirCooled') : nil
    legacy_hvac.model_add_doas(legacy, legacy_zones, hot_water_loop: legacy_hw, chilled_water_loop: legacy_chw, **kwargs)
    @composers.doas(composed, composed_zones, hot_water_loop: composed_hw, chilled_water_loop: composed_chw, **kwargs)
    [legacy, composed]
  end

  def test_doas_cv_default_parity
    legacy, composed = build_doas_pair
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getAirLoopHVACs.size)
    assert_equal(2, composed.getFanConstantVolumes.size)
    assert_equal(1, composed.getCoilCoolingDXTwoSpeeds.size)
    assert_equal(1, composed.getCoilHeatingDXSingleSpeeds.size)
    assert_equal(1, composed.getCoilHeatingElectrics.size)
  end

  # The LargeHotel prototype maps set an explicit supply fan maximum flow rate.
  def test_doas_fan_maximum_flow_rate_parity
    legacy, composed = build_doas_pair(fan_maximum_flow_rate: 4346.24464)
    assert_model_parity(legacy, composed)
    fan = composed.getFanConstantVolumeByName('DOAS Supply Fan').get
    assert_in_delta(OpenStudio.convert(4346.24464, 'cfm', 'm^3/s').get, fan.maximumFlowRate.get, 1e-6)
  end

  def test_doas_vav_parity
    legacy, composed = build_doas_pair(doas_type: 'DOASVAV')
    assert_model_parity(legacy, composed)
    assert_equal(2, composed.getFanVariableVolumes.size)
    assert_equal(2, composed.getAirTerminalSingleDuctVAVNoReheats.size)
  end

  def test_doas_vav_reheat_electric_parity
    legacy, composed = build_doas_pair(doas_type: 'DOASVAVReheat')
    assert_model_parity(legacy, composed)
    assert_equal(2, composed.getAirTerminalSingleDuctVAVReheats.size)
  end

  def test_doas_hw_chw_reheat_parity
    legacy, composed = build_doas_pair(doas_type: 'DOASVAVReheat', with_hw: true, with_chw: true)
    assert_model_parity(legacy, composed)
    # water coils: main heating + cooling + one reheat coil per zone
    assert_equal(3, composed.getCoilHeatingWaters.size)
    assert_equal(1, composed.getCoilCoolingWaters.size)
  end

  def test_doas_no_exhaust_fan_parity
    legacy, composed = build_doas_pair(include_exhaust_fan: false)
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getFanConstantVolumes.size)
  end

  def test_doas_dcv_economizer_parity
    legacy, composed = build_doas_pair(doas_type: 'DOASVAV', demand_control_ventilation: true, econo_ctrl_mthd: 'FixedDryBulb')
    assert_model_parity(legacy, composed)
    assert(composed.getControllerMechanicalVentilations.first.demandControlledVentilation)
  end

  def test_doas_multiple_zones_parity
    legacy, composed = build_doas_pair(zone_count: 4)
    assert_model_parity(legacy, composed)
    assert_equal(4, composed.getAirTerminalSingleDuctConstantVolumeNoReheats.size)
  end

  def test_doas_zero_oa_returns_false
    model, zones = model_with_zones(2) # bare zones: no design OA requirement
    assert_equal(false, @composers.doas(model, zones))
    assert_equal(0, model.getAirLoopHVACs.size)
  end

  def test_doas_skips_zero_oa_zones
    model, zones = model_with_oa_zones(2)
    bare = OpenStudio::Model::ThermalZone.new(model)
    bare.setName('Bare Zone')
    OpenStudio::Model::Space.new(model).setThermalZone(bare)
    @composers.doas(model, zones + [bare])
    # only the two OA zones get a terminal; the loop name still counts all three zones
    assert_equal(2, model.getAirTerminalSingleDuctConstantVolumeNoReheats.size)
    assert_equal('3 Zone DOAS', model.getAirLoopHVACs.first.name.get)
  end

  def test_doas_sizing_checklist
    _legacy, composed = build_doas_pair
    sizing = composed.getAirLoopHVACs.first.sizingSystem
    assert_equal('VentilationRequirement', sizing.typeofLoadtoSizeOn)
    assert(sizing.allOutdoorAirinCooling)
    assert(sizing.allOutdoorAirinHeating)
    assert_equal('Coincident', sizing.sizingOption)
    assert_in_delta(1.0, sizing.centralHeatingMaximumSystemAirFlowRatio.get, 0.001)
    assert_in_delta(OpenStudio.convert(60.0, 'F', 'C').get, sizing.centralCoolingDesignSupplyAirTemperature, 0.01)
    assert_in_delta(OpenStudio.convert(70.0, 'F', 'C').get, sizing.centralHeatingDesignSupplyAirTemperature, 0.01)
  end

  def test_doas_exhaust_fan_pressure_checklist
    _legacy, composed = build_doas_pair
    exhaust = composed.getFanConstantVolumes.find { |fan| fan.name.get == 'DOAS Exhaust Fan' }
    supply = composed.getFanConstantVolumes.find { |fan| fan.name.get == 'DOAS Supply Fan' }
    # exhaust runs 1 in. H2O below the supply fan
    assert_in_delta(supply.pressureRise - OpenStudio.convert(1.0, 'inH_{2}O', 'Pa').get, exhaust.pressureRise, 0.01)
  end

  def test_doas_zone_sizing_and_sequence_checklist
    _legacy, composed = build_doas_pair
    zone = composed.getThermalZones.min_by { |z| z.name.get }
    sizing = zone.sizingZone
    assert(sizing.accountforDedicatedOutdoorAirSystem)
    assert_equal('NeutralSupplyAir', sizing.dedicatedOutdoorAirSystemControlStrategy)
    assert_in_delta(1.0, sizing.heatingMaximumAirFlowFraction, 0.001)
    terminal = zone.equipment.first
    assert_in_delta(0.0, zone.sequentialCoolingFraction(terminal).get, 0.001)
    assert_in_delta(0.0, zone.sequentialHeatingFraction(terminal).get, 0.001)
  end

  def test_doas_hw_coil_convergence_tolerance
    _legacy, composed = build_doas_pair(with_hw: true)
    coil = composed.getCoilHeatingWaters.find { |c| c.name.get.include?('Htg Coil') }
    assert_in_delta(0.0001, coil.controllerWaterCoil.get.controllerConvergenceTolerance.get, 1e-8)
  end

  def test_doas_returns_air_loop
    model, zones = model_with_oa_zones(2)
    loop = @composers.doas(model, zones, system_name: 'My DOAS')
    assert(loop.to_AirLoopHVAC.is_initialized)
    assert_equal('My DOAS', loop.name.get)
  end

  def test_doas_forward_translates
    model, zones = model_with_oa_zones(2)
    @composers.doas(model, zones)
    ft = OpenStudio::EnergyPlus::ForwardTranslator.new
    ft.translateModel(model)
    assert_equal(0, ft.errors.size, ft.errors.map(&:logMessage).join("\n"))
  end

  # ---- DOAS cold supply (default DOE-prototype DOAS) ----

  def build_cold_supply_pair(zone_count: 2, with_hw: false, with_chw: false, **kwargs)
    legacy, legacy_zones = model_with_oa_zones(zone_count)
    composed, composed_zones = model_with_oa_zones(zone_count)
    legacy_hw = with_hw ? legacy_hvac.model_add_hw_loop(legacy, 'NaturalGas') : nil
    composed_hw = with_hw ? @hvac.model_add_hw_loop(composed, 'NaturalGas') : nil
    legacy_chw = with_chw ? legacy_hvac.model_add_chw_loop(legacy, chw_pumping_configuration: 'constant primary', chiller_cooling_type: 'AirCooled') : nil
    composed_chw = with_chw ? @hvac.model_add_chw_loop(composed, chw_pumping_configuration: 'constant primary', chiller_cooling_type: 'AirCooled') : nil
    legacy_hvac.model_add_doas_cold_supply(legacy, legacy_zones, hot_water_loop: legacy_hw, chilled_water_loop: legacy_chw, **kwargs)
    @composers.doas_cold_supply(composed, composed_zones, hot_water_loop: composed_hw, chilled_water_loop: composed_chw, **kwargs)
    [legacy, composed]
  end

  def test_cold_supply_default_parity
    legacy, composed = build_cold_supply_pair(zone_count: 3)
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getAirLoopHVACs.size)
    # supply fan only, no exhaust fan
    assert_equal(1, composed.getFanConstantVolumes.size)
    assert_equal(3, composed.getAirTerminalSingleDuctConstantVolumeNoReheats.size)
    assert_equal(1, composed.getCoilCoolingDXTwoSpeeds.size)
    assert_equal(1, composed.getCoilHeatingDXSingleSpeeds.size)
  end

  def test_cold_supply_hw_chw_parity
    legacy, composed = build_cold_supply_pair(with_hw: true, with_chw: true)
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getCoilHeatingWaters.size)
    assert_equal(1, composed.getCoilCoolingWaters.size)
  end

  # The three LargeHotel geometry maps set this on their 'DOAS Cold Supply' system.
  def test_cold_supply_fan_maximum_flow_rate_parity
    legacy, composed = build_cold_supply_pair(fan_maximum_flow_rate: 4346.24464)
    assert_model_parity(legacy, composed)
    fan = composed.getFanConstantVolumeByName('DOAS Supply Fan').get
    assert_in_delta(OpenStudio.convert(4346.24464, 'cfm', 'm^3/s').get, fan.maximumFlowRate.get, 1e-6)
  end

  def test_cold_supply_custom_name_and_temps_parity
    legacy, composed = build_cold_supply_pair(system_name: 'CS DOAS', clg_dsgn_sup_air_temp: 52.0, htg_dsgn_sup_air_temp: 58.0)
    assert_model_parity(legacy, composed)
    assert_equal('CS DOAS', composed.getAirLoopHVACs.first.name.get)
  end

  def test_cold_supply_checklist
    _legacy, composed = build_cold_supply_pair
    air_loop = composed.getAirLoopHVACs.first
    assert_equal('CycleOnAny', air_loop.nightCycleControlType)
    sizing = air_loop.sizingSystem
    assert_equal('VentilationRequirement', sizing.typeofLoadtoSizeOn)
    assert_in_delta(OpenStudio.convert(55.0, 'F', 'C').get, sizing.centralCoolingDesignSupplyAirTemperature, 0.01)
    assert_in_delta(OpenStudio.convert(60.0, 'F', 'C').get, sizing.centralHeatingDesignSupplyAirTemperature, 0.01)
    assert_equal('2 Zone DOAS OA Controller', composed.getControllerOutdoorAirs.first.name.get)
    assert_equal('FixedDryBulb', composed.getControllerOutdoorAirs.first.getEconomizerControlType)
    sizing_zone = composed.getThermalZones.min_by { |z| z.name.get }.sizingZone
    assert_equal('ColdSupplyAir', sizing_zone.dedicatedOutdoorAirSystemControlStrategy)
  end

  def test_cold_supply_zero_oa_returns_false
    model, zones = model_with_zones(2)
    assert_equal(false, @composers.doas_cold_supply(model, zones))
    assert_equal(0, model.getAirLoopHVACs.size)
  end

  def test_cold_supply_energy_recovery_unsupported
    model, zones = model_with_oa_zones(2)
    assert_raises(NotImplementedError) { @composers.doas_cold_supply(model, zones, energy_recovery: true) }
  end

  def test_cold_supply_forward_translates
    model, zones = model_with_oa_zones(2)
    @composers.doas_cold_supply(model, zones)
    ft = OpenStudio::EnergyPlus::ForwardTranslator.new
    ft.translateModel(model)
    assert_equal(0, ft.errors.size, ft.errors.map(&:logMessage).join("\n"))
  end

  # ---- CRAC (computer-room air conditioner) ----

  def build_crac_pair(zone_count: 1, climate_zone: 'ASHRAE 169-2013-5A', **kwargs)
    legacy, legacy_zones = model_with_zones(zone_count)
    composed, composed_zones = model_with_zones(zone_count)
    legacy_hvac.model_add_crac(legacy, legacy_zones, climate_zone, **kwargs)
    @composers.crac(composed, composed_zones, climate_zone, **kwargs)
    [legacy, composed]
  end

  def test_crac_default_parity
    legacy, composed = build_crac_pair
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getAirLoopHVACs.size)
    assert_equal(1, composed.getCoilCoolingDXSingleSpeeds.size)
    assert_equal(1, composed.getHumidifierSteamElectrics.size)
    assert_equal(1, composed.getSetpointManagerSingleZoneHumidityMinimums.size)
    assert_equal(1, composed.getZoneControlHumidistats.size)
  end

  def test_crac_cold_climate_economizer_parity
    legacy, composed = build_crac_pair(climate_zone: 'ASHRAE 169-2013-7A')
    assert_model_parity(legacy, composed)
    assert_equal('FixedDryBulb', composed.getControllerOutdoorAirs.first.getEconomizerControlType)
  end

  def test_crac_blow_through_parity
    legacy, composed = build_crac_pair(fan_location: 'BlowThrough')
    assert_model_parity(legacy, composed)
  end

  def test_crac_two_speed_parity
    legacy, composed = build_crac_pair(cooling_type: 'Two Speed DX AC')
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getCoilCoolingDXTwoSpeeds.size)
  end

  def test_crac_variable_volume_fan_parity
    legacy, composed = build_crac_pair(fan_type: 'VariableVolume')
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getFanVariableVolumes.size)
  end

  def test_crac_multiple_zones_parity
    legacy, composed = build_crac_pair(zone_count: 3)
    assert_model_parity(legacy, composed)
    assert_equal(3, composed.getAirLoopHVACs.size)
    assert_equal(3, composed.getHumidifierSteamElectrics.size)
  end

  def test_crac_checklist
    _legacy, composed = build_crac_pair
    air_loop = composed.getAirLoopHVACs.first
    assert_equal('Zone 1 CRAC', air_loop.name.get)
    sizing = air_loop.sizingSystem
    assert_in_delta(0.05, sizing.centralHeatingMaximumSystemAirFlowRatio.get, 0.001)
    assert_in_delta(OpenStudio.convert(64.4, 'F', 'C').get, sizing.preheatDesignTemperature, 0.01)
    assert_in_delta(OpenStudio.convert(80.6, 'F', 'C').get, sizing.precoolDesignTemperature, 0.01)
    # humidifier power is autosized (a new humidifier does not autosize power by default)
    assert(composed.getHumidifierSteamElectrics.first.isRatedPowerAutosized)
    diffuser = composed.getAirTerminalSingleDuctVAVNoReheats.first
    assert_in_delta(0.1, diffuser.constantMinimumAirFlowFraction.get, 0.001)
  end

  def test_crac_forward_translates
    model, zones = model_with_zones(2)
    @composers.crac(model, zones, 'ASHRAE 169-2013-5A')
    ft = OpenStudio::EnergyPlus::ForwardTranslator.new
    ft.translateModel(model)
    assert_equal(0, ft.errors.size, ft.errors.map(&:logMessage).join("\n"))
  end

  # ---- CRAH (computer-room air handler) ----

  def build_crah_pair(zone_count: 2, **kwargs)
    legacy, legacy_zones = model_with_zones(zone_count)
    composed, composed_zones = model_with_zones(zone_count)
    legacy_chw = legacy_hvac.model_add_chw_loop(legacy, chw_pumping_configuration: 'constant primary', chiller_cooling_type: 'AirCooled')
    composed_chw = @hvac.model_add_chw_loop(composed, chw_pumping_configuration: 'constant primary', chiller_cooling_type: 'AirCooled')
    legacy_hvac.model_add_crah(legacy, legacy_zones, chilled_water_loop: legacy_chw, **kwargs)
    @composers.crah(composed, composed_zones, chilled_water_loop: composed_chw, **kwargs)
    [legacy, composed]
  end

  def test_crah_default_parity
    legacy, composed = build_crah_pair
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getAirLoopHVACs.size)
    assert_equal(1, composed.getCoilCoolingWaters.size)
    assert_equal(1, composed.getHumidifierSteamElectrics.size)
    # each zone gets a humidistat, but only the last minimum-humidity SPM survives on the shared node
    assert_equal(2, composed.getZoneControlHumidistats.size)
    assert_equal(1, composed.getSetpointManagerSingleZoneHumidityMinimums.size)
  end

  def test_crah_single_zone_parity
    legacy, composed = build_crah_pair(zone_count: 1)
    assert_model_parity(legacy, composed)
  end

  def test_crah_multiple_zones_parity
    legacy, composed = build_crah_pair(zone_count: 4)
    assert_model_parity(legacy, composed)
    assert_equal(4, composed.getAirTerminalSingleDuctVAVNoReheats.size)
  end

  def test_crah_custom_name_parity
    legacy, composed = build_crah_pair(system_name: 'Big CRAH')
    assert_model_parity(legacy, composed)
    assert_equal('Big CRAH', composed.getAirLoopHVACs.first.name.get)
  end

  def test_crah_requires_chilled_water_loop
    model, zones = model_with_zones(2)
    assert_raises(ArgumentError) { @composers.crah(model, zones) }
  end

  def test_crah_checklist
    _legacy, composed = build_crah_pair
    air_loop = composed.getAirLoopHVACs.first
    assert_equal('Data Center CRAH', air_loop.name.get)
    assert_in_delta(0.3, air_loop.sizingSystem.centralHeatingMaximumSystemAirFlowRatio.get, 0.001)
    oa = composed.getControllerOutdoorAirs.first
    assert_equal('Data Center CRAH OA Controller', oa.name.get)
    assert_equal('FixedMinimum', oa.getMinimumLimitType)
    assert_equal('ZoneSum', oa.controllerMechanicalVentilation.systemOutdoorAirMethod)
  end

  def test_crah_forward_translates
    model, zones = model_with_zones(2)
    chw = @hvac.model_add_chw_loop(model, chw_pumping_configuration: 'constant primary', chiller_cooling_type: 'AirCooled')
    @composers.crah(model, zones, chilled_water_loop: chw)
    ft = OpenStudio::EnergyPlus::ForwardTranslator.new
    ft.translateModel(model)
    assert_equal(0, ft.errors.size, ft.errors.map(&:logMessage).join("\n"))
  end

  # ---- data center HVAC (water-to-air heat pump PSZ-AC) ----

  def build_data_center_pair(zone_count: 1, **kwargs)
    legacy, legacy_zones = model_with_zones(zone_count)
    composed, composed_zones = model_with_zones(zone_count)
    legacy_hw = legacy_hvac.model_add_hw_loop(legacy, 'NaturalGas')
    legacy_hp = legacy_hvac.model_add_hp_loop(legacy, heating_fuel: 'NaturalGas', cooling_fuel: 'Electricity', cooling_type: 'EvaporativeFluidCooler')
    composed_hw = @hvac.model_add_hw_loop(composed, 'NaturalGas')
    composed_hp = @hvac.model_add_hp_loop(composed, heating_fuel: 'NaturalGas', cooling_fuel: 'Electricity', cooling_type: 'EvaporativeFluidCooler')
    legacy_hvac.model_add_data_center_hvac(legacy, legacy_zones, legacy_hw, legacy_hp, **kwargs)
    @composers.data_center_hvac(composed, composed_zones, composed_hw, composed_hp, **kwargs)
    [legacy, composed]
  end

  def test_data_center_default_parity
    legacy, composed = build_data_center_pair
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getAirLoopHVACUnitarySystems.size)
    assert_equal(1, composed.getCoilCoolingWaterToAirHeatPumpEquationFits.size)
    assert_equal(1, composed.getCoilHeatingWaterToAirHeatPumpEquationFits.size)
  end

  def test_data_center_main_parity
    legacy, composed = build_data_center_pair(main_data_center: true)
    assert_model_parity(legacy, composed)
    # main data center adds a supplemental hot-water preheat coil, an electric preheat coil, and humidification
    assert_equal(1, composed.getCoilHeatingWaters.size)
    assert_equal(1, composed.getHumidifierSteamElectrics.size)
    assert_equal(1, composed.getZoneControlHumidistats.size)
    assert_equal(2, composed.getCoilHeatingElectrics.size)
  end

  def test_data_center_multiple_zones_parity
    legacy, composed = build_data_center_pair(zone_count: 2)
    assert_model_parity(legacy, composed)
    assert_equal(2, composed.getAirLoopHVACs.size)
  end

  def test_data_center_custom_name_parity
    legacy, composed = build_data_center_pair(system_name: 'DC HP')
    assert_model_parity(legacy, composed)
  end

  def test_data_center_checklist
    _legacy, composed = build_data_center_pair(main_data_center: true)
    unitary = composed.getAirLoopHVACUnitarySystems.first
    assert_equal('BlowThrough', unitary.fanPlacement.get)
    assert_in_delta(OpenStudio.convert(40.0, 'F', 'C').get, unitary.maximumOutdoorDryBulbTemperatureforSupplementalHeaterOperation, 0.01)
    # WAHP coils carry their default rated COPs and named performance curves
    assert_in_delta(4.2, composed.getCoilHeatingWaterToAirHeatPumpEquationFits.first.ratedHeatingCoefficientofPerformance, 0.01)
    assert_in_delta(3.4, composed.getCoilCoolingWaterToAirHeatPumpEquationFits.first.ratedCoolingCoefficientofPerformance, 0.01)
    spm = composed.getSetpointManagerSingleZoneReheats.first
    assert_in_delta(OpenStudio.convert(104.0, 'F', 'C').get, spm.maximumSupplyAirTemperature, 0.01)
  end

  def test_data_center_forward_translates
    model, zones = model_with_zones(1)
    hw = @hvac.model_add_hw_loop(model, 'NaturalGas')
    hp = @hvac.model_add_hp_loop(model, heating_fuel: 'NaturalGas', cooling_fuel: 'Electricity', cooling_type: 'EvaporativeFluidCooler')
    @composers.data_center_hvac(model, zones, hw, hp, main_data_center: true)
    ft = OpenStudio::EnergyPlus::ForwardTranslator.new
    ft.translateModel(model)
    assert_equal(0, ft.errors.size, ft.errors.map(&:logMessage).join("\n"))
  end

  # ---- PTAC (zone equipment) ----

  def build_ptac_pair(zone_count: 1, with_hw: false, **kwargs)
    legacy, legacy_zones = model_with_zones(zone_count)
    composed, composed_zones = model_with_zones(zone_count)
    legacy_hw = with_hw ? legacy_hvac.model_add_hw_loop(legacy, 'NaturalGas') : nil
    composed_hw = with_hw ? @hvac.model_add_hw_loop(composed, 'NaturalGas') : nil
    legacy_hvac.model_add_ptac(legacy, legacy_zones, hot_water_loop: legacy_hw, **kwargs)
    @composers.ptac(composed, composed_zones, hot_water_loop: composed_hw, **kwargs)
    [legacy, composed]
  end

  def test_ptac_default_parity
    legacy, composed = build_ptac_pair
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getZoneHVACPackagedTerminalAirConditioners.size)
    assert_equal(1, composed.getCoilCoolingDXTwoSpeeds.size)
    assert_equal(1, composed.getCoilHeatingGass.size)
    assert_equal(0, composed.getAirLoopHVACs.size) # zone equipment, no air loop
  end

  def test_ptac_single_speed_electric_parity
    legacy, composed = build_ptac_pair(cooling_type: 'Single Speed DX AC', heating_type: 'Electricity')
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getCoilCoolingDXSingleSpeeds.size)
    assert_equal(1, composed.getCoilHeatingElectrics.size)
  end

  def test_ptac_no_heat_parity
    legacy, composed = build_ptac_pair(heating_type: nil)
    assert_model_parity(legacy, composed)
  end

  def test_ptac_water_heat_parity
    legacy, composed = build_ptac_pair(heating_type: 'Water', with_hw: true)
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getCoilHeatingWaters.size)
  end

  def test_ptac_constant_volume_fan_parity
    legacy, composed = build_ptac_pair(fan_type: 'ConstantVolume')
    assert_model_parity(legacy, composed)
    ptac = composed.getZoneHVACPackagedTerminalAirConditioners.first
    assert_equal('Always On Discrete', ptac.supplyAirFanOperatingModeSchedule.name.get)
  end

  def test_ptac_no_ventilation_parity
    legacy, composed = build_ptac_pair(ventilation: false)
    assert_model_parity(legacy, composed)
    ptac = composed.getZoneHVACPackagedTerminalAirConditioners.first
    assert_in_delta(0.0, ptac.outdoorAirFlowRateDuringCoolingOperation.get, 1e-6)
  end

  def test_ptac_multiple_zones_parity
    legacy, composed = build_ptac_pair(zone_count: 3)
    assert_model_parity(legacy, composed)
    assert_equal(3, composed.getZoneHVACPackagedTerminalAirConditioners.size)
  end

  def test_ptac_water_heat_requires_loop
    model, zones = model_with_zones(1)
    assert_raises(ArgumentError) { @composers.ptac(model, zones, heating_type: 'Water') }
  end

  def test_ptac_checklist
    _legacy, composed = build_ptac_pair
    ptac = composed.getZoneHVACPackagedTerminalAirConditioners.first
    assert_equal('Zone 1 PTAC', ptac.name.get)
    assert_equal('DrawThrough', ptac.fanPlacement)
    assert(ptac.supplyAirFan.to_FanOnOff.is_initialized)
    sizing = composed.getThermalZones.first.sizingZone
    assert_in_delta(OpenStudio.convert(57.0, 'F', 'C').get, sizing.zoneCoolingDesignSupplyAirTemperature, 0.01)
    assert_in_delta(OpenStudio.convert(122.0, 'F', 'C').get, sizing.zoneHeatingDesignSupplyAirTemperature, 0.01)
  end

  def test_ptac_returns_units
    model, zones = model_with_zones(2)
    ptacs = @composers.ptac(model, zones)
    assert_equal(2, ptacs.size)
    assert(ptacs.first.to_ZoneHVACPackagedTerminalAirConditioner.is_initialized)
  end

  def test_ptac_forward_translates
    # single-speed DX: the PTAC default of two-speed DX is rejected by OpenStudio (PTACs require a
    # single-speed coil), a legacy quirk the composer reproduces but which is not forward-translatable
    model, zones = model_with_zones(2)
    @composers.ptac(model, zones, cooling_type: 'Single Speed DX AC', heating_type: 'Electricity')
    ft = OpenStudio::EnergyPlus::ForwardTranslator.new
    ft.translateModel(model)
    assert_equal(0, ft.errors.size, ft.errors.map(&:logMessage).join("\n"))
  end

  # ---- PTHP (zone equipment) ----

  def build_pthp_pair(zone_count: 1, **kwargs)
    legacy, legacy_zones = model_with_zones(zone_count)
    composed, composed_zones = model_with_zones(zone_count)
    legacy_hvac.model_add_pthp(legacy, legacy_zones, **kwargs)
    @composers.pthp(composed, composed_zones, **kwargs)
    [legacy, composed]
  end

  def test_pthp_default_parity
    legacy, composed = build_pthp_pair
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getZoneHVACPackagedTerminalHeatPumps.size)
    assert_equal(1, composed.getCoilHeatingDXSingleSpeeds.size)
    assert_equal(1, composed.getCoilCoolingDXSingleSpeeds.size)
    assert_equal(1, composed.getCoilHeatingElectrics.size) # supplemental
  end

  def test_pthp_constant_volume_parity
    legacy, composed = build_pthp_pair(fan_type: 'ConstantVolume')
    assert_model_parity(legacy, composed)
  end

  def test_pthp_no_ventilation_parity
    legacy, composed = build_pthp_pair(ventilation: false)
    assert_model_parity(legacy, composed)
    pthp = composed.getZoneHVACPackagedTerminalHeatPumps.first
    assert_in_delta(0.0, pthp.outdoorAirFlowRateDuringHeatingOperation.get, 1e-6)
  end

  def test_pthp_multiple_zones_parity
    legacy, composed = build_pthp_pair(zone_count: 3)
    assert_model_parity(legacy, composed)
    assert_equal(3, composed.getZoneHVACPackagedTerminalHeatPumps.size)
  end

  def test_pthp_returns_units
    model, zones = model_with_zones(2)
    pthps = @composers.pthp(model, zones)
    assert_equal(2, pthps.size)
    assert(pthps.first.to_ZoneHVACPackagedTerminalHeatPump.is_initialized)
  end

  # ---- unit heater (zone equipment) ----

  def build_unitheater_pair(zone_count: 1, with_hw: false, **kwargs)
    legacy, legacy_zones = model_with_zones(zone_count)
    composed, composed_zones = model_with_zones(zone_count)
    legacy_hw = with_hw ? legacy_hvac.model_add_hw_loop(legacy, 'NaturalGas') : nil
    composed_hw = with_hw ? @hvac.model_add_hw_loop(composed, 'NaturalGas') : nil
    legacy_hvac.model_add_unitheater(legacy, legacy_zones, hot_water_loop: legacy_hw, **kwargs)
    @composers.unitheater(composed, composed_zones, hot_water_loop: composed_hw, **kwargs)
    [legacy, composed]
  end

  def test_unitheater_gas_parity
    legacy, composed = build_unitheater_pair(heating_type: 'Gas')
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getZoneHVACUnitHeaters.size)
    assert_equal(1, composed.getCoilHeatingGass.size)
  end

  def test_unitheater_electric_parity
    legacy, composed = build_unitheater_pair(heating_type: 'Electricity')
    assert_model_parity(legacy, composed)
  end

  def test_unitheater_district_water_parity
    legacy, composed = build_unitheater_pair(heating_type: 'DistrictHeatingWater', with_hw: true)
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getCoilHeatingWaters.size)
  end

  def test_unitheater_fan_control_parity
    legacy, composed = build_unitheater_pair(heating_type: 'Gas', fan_control_type: 'OnOff')
    assert_model_parity(legacy, composed)
    assert_equal('OnOff', composed.getZoneHVACUnitHeaters.first.fanControlType)
  end

  def test_unitheater_checklist
    _legacy, composed = build_unitheater_pair(heating_type: 'Gas')
    assert_equal('Zone 1 Unit Heater', composed.getZoneHVACUnitHeaters.first.name.get)
    sizing = composed.getThermalZones.first.sizingZone
    assert_in_delta(1.0, sizing.heatingMaximumAirFlowFraction, 0.001)
  end

  # ---- four-pipe fan coil (zone equipment) ----

  def build_fcu_pair(zone_count: 1, with_hw: false, **kwargs)
    legacy, legacy_zones = model_with_zones(zone_count)
    composed, composed_zones = model_with_zones(zone_count)
    legacy_chw = legacy_hvac.model_add_chw_loop(legacy, chw_pumping_configuration: 'constant primary', chiller_cooling_type: 'AirCooled')
    composed_chw = @hvac.model_add_chw_loop(composed, chw_pumping_configuration: 'constant primary', chiller_cooling_type: 'AirCooled')
    legacy_hw = with_hw ? legacy_hvac.model_add_hw_loop(legacy, 'NaturalGas') : nil
    composed_hw = with_hw ? @hvac.model_add_hw_loop(composed, 'NaturalGas') : nil
    legacy_hvac.model_add_four_pipe_fan_coil(legacy, legacy_zones, legacy_chw, hot_water_loop: legacy_hw, **kwargs)
    @composers.four_pipe_fan_coil(composed, composed_zones, composed_chw, hot_water_loop: composed_hw, **kwargs)
    [legacy, composed]
  end

  def test_fcu_no_heat_parity
    legacy, composed = build_fcu_pair
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getZoneHVACFourPipeFanCoils.size)
    assert_equal(1, composed.getCoilCoolingWaters.size)
  end

  def test_fcu_hot_water_parity
    legacy, composed = build_fcu_pair(with_hw: true)
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getCoilHeatingWaters.size)
  end

  def test_fcu_variable_fan_parity
    legacy, composed = build_fcu_pair(with_hw: true, capacity_control_method: 'VariableFanVariableFlow')
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getFanVariableVolumes.size)
  end

  def test_fcu_ventilation_parity
    legacy, composed = build_fcu_pair(with_hw: true, ventilation: true)
    assert_model_parity(legacy, composed)
  end

  def test_fcu_no_ventilation_zeroes_oa
    _legacy, composed = build_fcu_pair(with_hw: true)
    fcu = composed.getZoneHVACFourPipeFanCoils.first
    assert_in_delta(0.0, fcu.maximumOutdoorAirFlowRate.get, 1e-6)
  end

  def test_fcu_multiple_zones_parity
    legacy, composed = build_fcu_pair(with_hw: true, zone_count: 3)
    assert_model_parity(legacy, composed)
    assert_equal(3, composed.getZoneHVACFourPipeFanCoils.size)
  end

  def test_fcu_requires_chilled_water_loop
    model, zones = model_with_zones(1)
    assert_raises(ArgumentError) { @composers.four_pipe_fan_coil(model, zones, nil) }
  end

  def test_fcu_forward_translates
    model, zones = model_with_zones(2)
    chw = @hvac.model_add_chw_loop(model, chw_pumping_configuration: 'constant primary', chiller_cooling_type: 'AirCooled')
    hw = @hvac.model_add_hw_loop(model, 'NaturalGas')
    @composers.four_pipe_fan_coil(model, zones, chw, hot_water_loop: hw)
    ft = OpenStudio::EnergyPlus::ForwardTranslator.new
    ft.translateModel(model)
    assert_equal(0, ft.errors.size, ft.errors.map(&:logMessage).join("\n"))
  end

  # ---- baseboard (zone equipment) ----

  def test_baseboard_electric_parity
    legacy, legacy_zones = model_with_zones(2)
    composed, composed_zones = model_with_zones(2)
    legacy_hvac.model_add_baseboard(legacy, legacy_zones)
    @composers.baseboard(composed, composed_zones)
    assert_model_parity(legacy, composed)
    assert_equal(2, composed.getZoneHVACBaseboardConvectiveElectrics.size)
  end

  def test_baseboard_hydronic_parity
    legacy, legacy_zones = model_with_zones(2)
    composed, composed_zones = model_with_zones(2)
    legacy_hw = legacy_hvac.model_add_hw_loop(legacy, 'NaturalGas')
    composed_hw = @hvac.model_add_hw_loop(composed, 'NaturalGas')
    legacy_hvac.model_add_baseboard(legacy, legacy_zones, hot_water_loop: legacy_hw)
    @composers.baseboard(composed, composed_zones, hot_water_loop: composed_hw)
    assert_model_parity(legacy, composed)
    assert_equal(2, composed.getZoneHVACBaseboardConvectiveWaters.size)
    assert_equal(2, composed.getCoilHeatingWaterBaseboards.size)
  end

  def test_baseboard_returns_units
    model, zones = model_with_zones(2)
    baseboards = @composers.baseboard(model, zones)
    assert_equal(2, baseboards.size)
    assert(baseboards.first.to_ZoneHVACBaseboardConvectiveElectric.is_initialized)
  end

  # ---- window AC (zone equipment) ----

  def test_window_ac_parity
    legacy, legacy_zones = model_with_zones(2)
    composed, composed_zones = model_with_zones(2)
    legacy_hvac.model_add_window_ac(legacy, legacy_zones)
    @composers.window_ac(composed, composed_zones)
    assert_model_parity(legacy, composed)
    assert_equal(2, composed.getZoneHVACPackagedTerminalAirConditioners.size)
    assert_equal(2, composed.getCoilCoolingDXSingleSpeeds.size)
  end

  def test_window_ac_checklist
    model, zones = model_with_zones(1)
    @composers.window_ac(model, zones)
    coil = model.getCoilCoolingDXSingleSpeeds.first
    assert_in_delta(0.65, coil.ratedSensibleHeatRatio.get, 0.001)
    assert_in_delta(0.9, coil.evaporativeCondenserEffectiveness, 0.001)
    assert_in_delta(2.0, coil.basinHeaterSetpointTemperature, 0.001)
  end

  # ---- water-source heat pump (zone equipment) ----

  def build_wshp_pair(zone_count: 1, **kwargs)
    legacy, legacy_zones = model_with_zones(zone_count)
    composed, composed_zones = model_with_zones(zone_count)
    legacy_cond = OpenStudio::Model::PlantLoop.new(legacy)
    legacy_cond.setName('Ambient Loop')
    composed_cond = OpenStudio::Model::PlantLoop.new(composed)
    composed_cond.setName('Ambient Loop')
    legacy_hvac.model_add_water_source_hp(legacy, legacy_zones, legacy_cond, **kwargs)
    @composers.water_source_hp(composed, composed_zones, composed_cond, **kwargs)
    [legacy, composed]
  end

  def test_water_source_hp_parity
    legacy, composed = build_wshp_pair
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getZoneHVACWaterToAirHeatPumps.size)
    assert_equal(1, composed.getCoilCoolingWaterToAirHeatPumpEquationFits.size)
    assert_equal(1, composed.getCoilHeatingWaterToAirHeatPumpEquationFits.size)
  end

  def test_water_source_hp_no_ventilation_parity
    legacy, composed = build_wshp_pair(ventilation: false)
    assert_model_parity(legacy, composed)
    wshp = composed.getZoneHVACWaterToAirHeatPumps.first
    assert_in_delta(0.0, wshp.outdoorAirFlowRateDuringCoolingOperation.get, 1e-6)
  end

  def test_water_source_hp_multiple_zones_parity
    legacy, composed = build_wshp_pair(zone_count: 3)
    assert_model_parity(legacy, composed)
    assert_equal(3, composed.getZoneHVACWaterToAirHeatPumps.size)
  end

  # ---- ideal air loads (zone equipment) ----

  def build_ideal_pair(zone_count: 1, oa: true, **kwargs)
    builder = oa ? :model_with_oa_zones : :model_with_zones
    legacy, legacy_zones = send(builder, zone_count)
    composed, composed_zones = send(builder, zone_count)
    legacy_hvac.model_add_ideal_air_loads(legacy, legacy_zones, **kwargs)
    @composers.ideal_air_loads(composed, composed_zones, **kwargs)
    [legacy, composed]
  end

  def test_ideal_air_loads_parity
    legacy, composed = build_ideal_pair
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getZoneHVACIdealLoadsAirSystems.size)
  end

  def test_ideal_air_loads_dcv_parity
    legacy, composed = build_ideal_pair(enable_dcv: true)
    assert_model_parity(legacy, composed)
    assert_equal('OccupancySchedule', composed.getZoneHVACIdealLoadsAirSystems.first.demandControlledVentilationType)
  end

  def test_ideal_air_loads_heat_recovery_parity
    legacy, composed = build_ideal_pair(heat_recovery_type: 'Sensible')
    assert_model_parity(legacy, composed)
    assert_equal('Sensible', composed.getZoneHVACIdealLoadsAirSystems.first.heatRecoveryType)
  end

  def test_ideal_air_loads_no_oa_parity
    legacy, composed = build_ideal_pair(oa: false, include_outdoor_air: false)
    assert_model_parity(legacy, composed)
  end

  def test_ideal_air_loads_output_meters_unsupported
    model, zones = model_with_zones(1)
    assert_raises(NotImplementedError) { @composers.ideal_air_loads(model, zones, add_output_meters: true) }
  end

  # ---- high-temperature radiant (zone equipment) ----

  # Build zones each carrying a dual-setpoint thermostat, needed by high-temp radiant.
  def model_with_thermostat_zones(count)
    model = OpenStudio::Model::Model.new
    htg = OpenStudio::Model::ScheduleConstant.new(model)
    htg.setName('Htg Setpoint')
    htg.setValue(20.0)
    clg = OpenStudio::Model::ScheduleConstant.new(model)
    clg.setName('Clg Setpoint')
    clg.setValue(24.0)
    zones = Array.new(count) do |i|
      zone = OpenStudio::Model::ThermalZone.new(model)
      zone.setName("Zone #{i + 1}")
      OpenStudio::Model::Space.new(model).setThermalZone(zone)
      thermostat = OpenStudio::Model::ThermostatSetpointDualSetpoint.new(model)
      thermostat.setHeatingSetpointTemperatureSchedule(htg)
      thermostat.setCoolingSetpointTemperatureSchedule(clg)
      zone.setThermostatSetpointDualSetpoint(thermostat)
      zone
    end
    [model, zones]
  end

  def build_high_temp_radiant_pair(zone_count: 1, **kwargs)
    legacy, legacy_zones = model_with_thermostat_zones(zone_count)
    composed, composed_zones = model_with_thermostat_zones(zone_count)
    legacy_hvac.model_add_high_temp_radiant(legacy, legacy_zones, **kwargs)
    @composers.high_temp_radiant(composed, composed_zones, **kwargs)
    [legacy, composed]
  end

  def test_high_temp_radiant_gas_parity
    legacy, composed = build_high_temp_radiant_pair
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getZoneHVACHighTemperatureRadiants.size)
    assert_equal('NaturalGas', composed.getZoneHVACHighTemperatureRadiants.first.fuelType)
  end

  def test_high_temp_radiant_electric_parity
    legacy, composed = build_high_temp_radiant_pair(heating_type: 'Electric')
    assert_model_parity(legacy, composed)
    # 'Electric' is not a valid ZoneHVACHighTemperatureRadiant fuel string, so OpenStudio rejects it and
    # the fuel stays NaturalGas in both the legacy method and the composer (a legacy quirk).
    assert_equal('NaturalGas', composed.getZoneHVACHighTemperatureRadiants.first.fuelType)
  end

  def test_high_temp_radiant_multiple_zones_parity
    legacy, composed = build_high_temp_radiant_pair(zone_count: 2)
    assert_model_parity(legacy, composed)
    assert_equal(2, composed.getZoneHVACHighTemperatureRadiants.size)
  end

  def test_high_temp_radiant_requires_thermostat
    model, zones = model_with_zones(1) # no thermostats
    assert_raises(ArgumentError) { @composers.high_temp_radiant(model, zones) }
  end

  def test_high_temp_radiant_checklist
    _legacy, composed = build_high_temp_radiant_pair
    radiant = composed.getZoneHVACHighTemperatureRadiants.first
    assert_in_delta(0.8, radiant.combustionEfficiency, 0.001)
    assert_in_delta(0.8, radiant.fractionofInputConvertedtoRadiantEnergy, 0.001)
    assert_equal('Htg Setpoint', radiant.heatingSetpointTemperatureSchedule.get.name.get)
  end

  # ---- split-system AC (single air loop, all zones) ----

  def build_split_ac_pair(zone_count: 2, **kwargs)
    legacy, legacy_zones = model_with_zones(zone_count)
    composed, composed_zones = model_with_zones(zone_count)
    legacy_hvac.model_add_split_ac(legacy, legacy_zones, **kwargs)
    @composers.split_ac(composed, composed_zones, **kwargs)
    [legacy, composed]
  end

  def test_split_ac_default_parity
    legacy, composed = build_split_ac_pair
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getAirLoopHVACs.size)
    assert_equal(1, composed.getCoilCoolingDXTwoSpeeds.size)
  end

  def test_split_ac_gas_heat_electric_backup_parity
    legacy, composed = build_split_ac_pair(heating_type: 'Gas', supplemental_heating_type: 'Electric')
    assert_model_parity(legacy, composed)
    # the gas main heating coil carries a part-load fraction correlation curve
    gas = composed.getCoilHeatingGass.find { |coil| coil.name.get.include?('Gas Htg Coil') }
    assert(gas.partLoadFractionCorrelationCurve.is_initialized)
  end

  def test_split_ac_single_speed_dx_parity
    legacy, composed = build_split_ac_pair(cooling_type: 'Single Speed DX AC')
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getCoilCoolingDXSingleSpeeds.size)
  end

  def test_split_ac_constant_volume_fan_parity
    legacy, composed = build_split_ac_pair(fan_type: 'ConstantVolume')
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getFanConstantVolumes.size)
  end

  def test_split_ac_no_supplemental_parity
    legacy, composed = build_split_ac_pair(supplemental_heating_type: nil)
    assert_model_parity(legacy, composed)
  end

  def test_split_ac_multiple_zones_parity
    legacy, composed = build_split_ac_pair(zone_count: 3)
    assert_model_parity(legacy, composed)
    assert_equal(3, composed.getAirTerminalSingleDuctConstantVolumeNoReheats.size)
  end

  def test_split_ac_checklist
    _legacy, composed = build_split_ac_pair
    air_loop = composed.getAirLoopHVACs.first
    assert_equal('NonCoincident', air_loop.sizingSystem.sizingOption)
    spm = composed.getSetpointManagerSingleZoneReheats.first
    assert_in_delta(OpenStudio.convert(122.0, 'F', 'C').get, spm.maximumSupplyAirTemperature, 0.01)
  end

  # ---- minisplit heat pump (one air loop per zone) ----

  def build_minisplit_pair(zone_count: 1, **kwargs)
    legacy, legacy_zones = model_with_zones(zone_count)
    composed, composed_zones = model_with_zones(zone_count)
    legacy_hvac.model_add_minisplit_hp(legacy, legacy_zones, **kwargs)
    @composers.minisplit_hp(composed, composed_zones, **kwargs)
    [legacy, composed]
  end

  def test_minisplit_default_parity
    legacy, composed = build_minisplit_pair
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getAirLoopHVACUnitarySystems.size)
    assert_equal(1, composed.getCoilHeatingDXSingleSpeeds.size)
    assert_equal(1, composed.getCoilCoolingDXTwoSpeeds.size)
    assert_equal(0, composed.getControllerOutdoorAirs.size) # no outdoor air system
  end

  def test_minisplit_single_speed_dx_parity
    legacy, composed = build_minisplit_pair(cooling_type: 'Single Speed DX AC')
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getCoilCoolingDXSingleSpeeds.size)
  end

  def test_minisplit_heat_pump_cooling_parity
    legacy, composed = build_minisplit_pair(cooling_type: 'Single Speed Heat Pump')
    assert_model_parity(legacy, composed)
  end

  def test_minisplit_multiple_zones_parity
    legacy, composed = build_minisplit_pair(zone_count: 3)
    assert_model_parity(legacy, composed)
    assert_equal(3, composed.getAirLoopHVACs.size)
  end

  def test_minisplit_checklist
    _legacy, composed = build_minisplit_pair
    coil = composed.getCoilHeatingDXSingleSpeeds.first
    assert_in_delta(OpenStudio.convert(-30.0, 'F', 'C').get, coil.minimumOutdoorDryBulbTemperatureforCompressorOperation, 0.01)
    assert_in_delta(0.0, coil.crankcaseHeaterCapacity, 0.001)
    unitary = composed.getAirLoopHVACUnitarySystems.first
    assert_equal('BlowThrough', unitary.fanPlacement.get)
    assert_in_delta(OpenStudio.convert(200.0, 'F', 'C').get, unitary.maximumSupplyAirTemperature.get, 0.01)
  end

  def test_minisplit_forward_translates
    model, zones = model_with_zones(2)
    @composers.minisplit_hp(model, zones)
    ft = OpenStudio::EnergyPlus::ForwardTranslator.new
    ft.translateModel(model)
    assert_equal(0, ft.errors.size, ft.errors.map(&:logMessage).join("\n"))
  end

  # ---- residential ERV (zone equipment) ----

  def build_res_erv_pair(zone_count: 1, oa: nil)
    legacy, legacy_zones = model_with_zones(zone_count)
    composed, composed_zones = model_with_zones(zone_count)
    if oa.nil?
      legacy_hvac.model_add_residential_erv(legacy, legacy_zones)
      @composers.residential_erv(composed, composed_zones)
    else
      legacy_hvac.model_add_residential_erv(legacy, legacy_zones, oa)
      @composers.residential_erv(composed, composed_zones, oa)
    end
    [legacy, composed]
  end

  def test_residential_erv_parity
    legacy, composed = build_res_erv_pair
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getZoneHVACEnergyRecoveryVentilators.size)
    assert_equal(1, composed.getZoneHVACEnergyRecoveryVentilatorControllers.size)
    assert_equal(1, composed.getHeatExchangerAirToAirSensibleAndLatents.size)
    assert_equal(2, composed.getFanOnOffs.size)
  end

  def test_residential_erv_per_area_parity
    legacy, composed = build_res_erv_pair(oa: 0.001)
    assert_model_parity(legacy, composed)
  end

  def test_residential_erv_multiple_zones_parity
    legacy, composed = build_res_erv_pair(zone_count: 3)
    assert_model_parity(legacy, composed)
    assert_equal(3, composed.getZoneHVACEnergyRecoveryVentilators.size)
  end

  def test_residential_erv_checklist
    _legacy, composed = build_res_erv_pair
    hx = composed.getHeatExchangerAirToAirSensibleAndLatents.first
    assert_equal('Rotary', hx.heatExchangerType)
    assert_equal('ExhaustOnly', hx.frostControlType)
    assert_in_delta(-23.3, hx.thresholdTemperature, 0.01)
    fan = composed.getFanOnOffs.first
    assert_in_delta(270.64755, fan.pressureRise, 0.01)
    assert_in_delta(0.48, fan.motorEfficiency, 0.001)
    assert_in_delta(0.303158, fan.fanTotalEfficiency, 0.0001)
  end

  def test_residential_erv_returns_units
    model, zones = model_with_zones(2)
    ervs = @composers.residential_erv(model, zones)
    assert_equal(2, ervs.size)
    assert(ervs.first.to_ZoneHVACEnergyRecoveryVentilator.is_initialized)
  end

  # ---- residential ventilator (zone equipment) ----

  def test_residential_ventilator_parity
    legacy, legacy_zones = model_with_zones(2)
    composed, composed_zones = model_with_zones(2)
    legacy_hvac.model_add_residential_ventilator(legacy, legacy_zones)
    @composers.residential_ventilator(composed, composed_zones)
    assert_model_parity(legacy, composed)
    assert_equal(2, composed.getZoneHVACUnitVentilators.size)
    # each zone gets a disconnected zone exhaust fan
    assert_equal(2, composed.getFanZoneExhausts.size)
  end

  # ---- ground heat exchanger loop ----

  def test_ground_hx_loop_parity
    legacy = OpenStudio::Model::Model.new
    composed = OpenStudio::Model::Model.new
    legacy_hvac.model_add_ground_hx_loop(legacy)
    @composers.ground_hx_loop(composed)
    assert_model_parity(legacy, composed)
  end

  def test_ground_hx_loop_checklist
    model = OpenStudio::Model::Model.new
    loop = @composers.ground_hx_loop(model)
    assert_equal("Ground HX Loop", loop.name.get)
    assert_in_delta(5.0, loop.minimumLoopTemperature, 1e-9)
    assert_in_delta(80.0, loop.maximumLoopTemperature, 1e-9)
    source = model.getPlantComponentTemperatureSources.first
    assert_equal("Ground HX", source.name.get)
    assert_equal("Scheduled", source.temperatureSpecificationType)
    assert_equal("Ground HX Temp Sch", source.sourceTemperatureSchedule.get.name.get)
    assert_equal(1, model.getScheduleConstants.size, "one shared constant schedule")
    assert_equal(1, model.getEnergyManagementSystemPrograms.size)
  end

  # The EMS reset line must match the legacy program text, not just its object count.
  def test_ground_hx_loop_ems_program_body_parity
    legacy = OpenStudio::Model::Model.new
    composed = OpenStudio::Model::Model.new
    legacy_hvac.model_add_ground_hx_loop(legacy)
    @composers.ground_hx_loop(composed)
    reset_line = lambda do |model|
      body = model.getEnergyManagementSystemPrograms.first.body
      body.lines.map(&:strip).find { |line| line.start_with?("SET Tout") }
    end
    assert_equal(reset_line.call(legacy), reset_line.call(composed))
  end

  def test_district_ambient_loop_parity
    legacy = OpenStudio::Model::Model.new
    composed = OpenStudio::Model::Model.new
    legacy_hvac.model_add_district_ambient_loop(legacy)
    @composers.district_ambient_loop(composed)
    assert_model_parity(legacy, composed)
  end

  def test_district_ambient_loop_checklist
    model = OpenStudio::Model::Model.new
    loop = @composers.district_ambient_loop(model)
    assert_equal("Ambient Loop", loop.name.get)
    assert_in_delta(OpenStudio.convert(102.2, "F", "C").get, loop.sizingPlant.designLoopExitTemperature, 1e-6)
    assert_equal(1, model.getDistrictCoolings.size)
    spm = model.getSetpointManagerScheduledDualSetpoints.first
    assert_equal("Ambient Loop Supply Water Setpoint Manager", spm.name.get)
    assert_equal("Ambient Loop High Temp - 90F", spm.highSetpointSchedule.get.name.get)
    assert_equal("Ambient Loop Low Temp - 41F", spm.lowSetpointSchedule.get.name.get)
    assert_in_delta(1_000_000_000_000, model.getDistrictCoolings.first.nominalCapacity.get, 1.0)
  end

  # ---- exhaust fans and zone ventilation ----

  def build_exhaust_fan_pair(zone_count: 2, **kwargs)
    legacy, legacy_zones = model_with_zones(zone_count)
    composed, composed_zones = model_with_zones(zone_count)
    legacy_hvac.model_add_exhaust_fan(legacy, legacy_zones, **kwargs)
    @composers.exhaust_fan(composed, composed_zones, **kwargs)
    [legacy, composed]
  end

  def test_exhaust_fan_parity
    legacy, composed = build_exhaust_fan_pair(flow_rate: 0.5)
    assert_model_parity(legacy, composed)
    assert_equal(2, composed.getFanZoneExhausts.size)
  end

  def test_exhaust_fan_checklist
    _legacy, composed = build_exhaust_fan_pair(zone_count: 1, flow_rate: 0.5)
    fan = composed.getFanZoneExhausts.first
    assert_equal('Zone 1 Exhaust Fan', fan.name.get)
    assert_in_delta(0.5, fan.maximumFlowRate.get, 1e-9)
    assert_equal('Decoupled', fan.systemAvailabilityManagerCouplingMode)
    assert(fan.thermalZone.is_initialized)
  end

  # A per-zone array assigns each flow rate to the zone at the same index.
  def test_exhaust_fan_flow_rate_array_parity
    legacy, composed = build_exhaust_fan_pair(flow_rate: [0.25, 0.75])
    assert_model_parity(legacy, composed)
    flows = composed.getFanZoneExhausts.map { |f| f.maximumFlowRate.get }.sort
    assert_in_delta(0.25, flows.first, 1e-9)
    assert_in_delta(0.75, flows.last, 1e-9)
  end

  def test_exhaust_fan_schedules_parity
    legacy, legacy_zones = model_with_zones(1)
    composed, composed_zones = model_with_zones(1)
    [[legacy, legacy_zones], [composed, composed_zones]].each do |model, zones|
      fraction = OpenStudio::Model::ScheduleConstant.new(model)
      fraction.setName('Exhaust Fraction')
      balanced = OpenStudio::Model::ScheduleConstant.new(model)
      balanced.setName('Balanced Fraction')
      args = { flow_rate: 0.5, flow_fraction_schedule: fraction, balanced_exhaust_fraction_schedule: balanced }
      if model == legacy
        legacy_hvac.model_add_exhaust_fan(model, zones, **args)
      else
        @composers.exhaust_fan(model, zones, **args)
      end
    end
    assert_model_parity(legacy, composed)
    fan = composed.getFanZoneExhausts.first
    assert_equal('Exhaust Fraction', fan.flowFractionSchedule.get.name.get)
    assert_equal('Balanced Fraction', fan.balancedExhaustFractionSchedule.get.name.get)
  end

  def build_zone_ventilation_pair(zone_count: 2, **kwargs)
    legacy, legacy_zones = model_with_zones(zone_count)
    composed, composed_zones = model_with_zones(zone_count)
    legacy_hvac.model_add_zone_ventilation(legacy, legacy_zones, **kwargs)
    @composers.zone_ventilation(composed, composed_zones, **kwargs)
    [legacy, composed]
  end

  def test_zone_ventilation_exhaust_parity
    legacy, composed = build_zone_ventilation_pair(ventilation_type: 'Exhaust', flow_rate: 0.1)
    assert_model_parity(legacy, composed)
    assert_equal(2, composed.getZoneVentilationDesignFlowRates.size)
  end

  def test_zone_ventilation_natural_parity
    legacy, composed = build_zone_ventilation_pair(ventilation_type: 'Natural', flow_rate: 0.1)
    assert_model_parity(legacy, composed)
  end

  def test_zone_ventilation_intake_parity
    legacy, composed = build_zone_ventilation_pair(ventilation_type: 'Intake', flow_rate: 0.002)
    assert_model_parity(legacy, composed)
  end

  # Each ventilation type carries its own fan and control-temperature envelope.
  def test_zone_ventilation_intake_checklist
    _legacy, composed = build_zone_ventilation_pair(zone_count: 1, ventilation_type: 'Intake', flow_rate: 0.002)
    vent = composed.getZoneVentilationDesignFlowRates.first
    assert_equal('Zone 1 Ventilation', vent.name.get)
    assert_equal('Intake', vent.ventilationType)
    assert_in_delta(0.002, vent.flowRateperZoneFloorArea, 1e-9)
    assert_in_delta(49.8, vent.fanPressureRise, 1e-9)
    assert_in_delta(0.53625, vent.fanTotalEfficiency, 1e-9)
    assert_in_delta(7.5, vent.minimumIndoorTemperature, 1e-9)
    assert_in_delta(-27.5, vent.deltaTemperature, 1e-9)
    assert_in_delta(-30.0, vent.minimumOutdoorTemperature, 1e-9)
    assert_in_delta(6.0, vent.maximumWindSpeed, 1e-9)
  end

  def test_zone_ventilation_requires_a_flow_rate
    model, zones = model_with_zones(1)
    assert_raises(ArgumentError) { @composers.zone_ventilation(model, zones, ventilation_type: 'Exhaust') }
  end

  def test_residential_ventilator_checklist
    model, zones = model_with_zones(1)
    @composers.residential_ventilator(model, zones)
    exhaust = model.getFanZoneExhausts.first
    assert_equal('Zone 1 Exhaust Fan', exhaust.name.get)
    assert_in_delta(233.6875, exhaust.pressureRise, 0.01)
    assert_in_delta(0.303158, exhaust.fanEfficiency, 0.0001)
    assert_in_delta(OpenStudio.convert(55.0, 'cfm', 'm^3/s').get, exhaust.maximumFlowRate.get, 1e-6)
  end

  def test_residential_ventilator_returns_units
    model, zones = model_with_zones(2)
    units = @composers.residential_ventilator(model, zones)
    assert_equal(2, units.size)
    assert(units.first.to_ZoneHVACUnitVentilator.is_initialized)
  end

  # ---- evaporative cooler (per-zone air loop with EMS availability control) ----

  def build_evap_pair(zone_count: 1)
    legacy, legacy_zones = model_with_zones(zone_count)
    composed, composed_zones = model_with_zones(zone_count)
    legacy_hvac.model_add_evap_cooler(legacy, legacy_zones)
    @composers.evap_cooler(composed, composed_zones)
    [legacy, composed]
  end

  def test_evap_cooler_default_parity
    legacy, composed = build_evap_pair
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getAirLoopHVACs.size)
    assert_equal(1, composed.getEvaporativeCoolerDirectResearchSpecials.size)
    # the EMS availability control objects
    assert_equal(1, composed.getEnergyManagementSystemSensors.size)
    assert_equal(1, composed.getEnergyManagementSystemActuators.size)
    assert_equal(1, composed.getEnergyManagementSystemPrograms.size)
    assert_equal(1, composed.getEnergyManagementSystemProgramCallingManagers.size)
  end

  def test_evap_cooler_multiple_zones_parity
    legacy, composed = build_evap_pair(zone_count: 3)
    assert_model_parity(legacy, composed)
    assert_equal(3, composed.getAirLoopHVACs.size)
    # one program per zone, all on a single calling manager
    assert_equal(3, composed.getEnergyManagementSystemPrograms.size)
    assert_equal(1, composed.getEnergyManagementSystemProgramCallingManagers.size)
    assert_equal(3, composed.getEnergyManagementSystemProgramCallingManagers.first.programs.size)
  end

  def test_evap_cooler_checklist
    _legacy, composed = build_evap_pair
    cooler = composed.getEvaporativeCoolerDirectResearchSpecials.first
    assert_in_delta(0.9, cooler.coolerDesignEffectiveness, 0.001)
    assert_in_delta(90.0, cooler.waterPumpPowerSizingFactor, 0.001)
    pcm = composed.getEnergyManagementSystemProgramCallingManagers.first
    assert_equal('AfterPredictorAfterHVACManagers', pcm.callingPoint)
    spm = composed.getSetpointManagerFollowOutdoorAirTemperatures.first
    assert_equal('OutdoorAirWetBulb', spm.referenceTemperatureType)
  end

  def test_evap_cooler_forward_translates
    model, zones = model_with_zones(2)
    @composers.evap_cooler(model, zones)
    ft = OpenStudio::EnergyPlus::ForwardTranslator.new
    ft.translateModel(model)
    assert_equal(0, ft.errors.size, ft.errors.map(&:logMessage).join("\n"))
  end

  # ---- zone ERV (zone equipment with computed DOAS sizing) ----

  # Build zones each with a 10x10 floor surface and a per-area design outdoor air object, so the
  # zone's outdoor air rate per floor area (used for the ERV ventilation rate) is finite.
  def model_with_floor_oa_zones(count)
    model = OpenStudio::Model::Model.new
    zones = Array.new(count) do |i|
      zone = OpenStudio::Model::ThermalZone.new(model)
      zone.setName("Zone #{i + 1}")
      space = OpenStudio::Model::Space.new(model)
      space.setThermalZone(zone)
      points = OpenStudio::Point3dVector.new
      [[0, 0, 0], [0, 10, 0], [10, 10, 0], [10, 0, 0]].each { |x, y, z| points << OpenStudio::Point3d.new(x, y, z) }
      surface = OpenStudio::Model::Surface.new(points, model)
      surface.setSpace(space)
      surface.setSurfaceType('Floor')
      dsn_oa = OpenStudio::Model::DesignSpecificationOutdoorAir.new(model)
      dsn_oa.setName("Zone #{i + 1} OA")
      dsn_oa.setOutdoorAirMethod('Sum')
      dsn_oa.setOutdoorAirFlowperFloorArea(0.0003)
      space.setDesignSpecificationOutdoorAir(dsn_oa)
      zone
    end
    [model, zones]
  end

  def build_zone_erv_pair(zone_count: 1)
    legacy, legacy_zones = model_with_floor_oa_zones(zone_count)
    composed, composed_zones = model_with_floor_oa_zones(zone_count)
    legacy_hvac.model_add_zone_erv(legacy, legacy_zones)
    @composers.zone_erv(composed, composed_zones)
    [legacy, composed]
  end

  def test_zone_erv_default_parity
    legacy, composed = build_zone_erv_pair
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getZoneHVACEnergyRecoveryVentilators.size)
    assert_equal(1, composed.getHeatExchangerAirToAirSensibleAndLatents.size)
    assert_equal(2, composed.getFanOnOffs.size)
  end

  def test_zone_erv_multiple_zones_parity
    legacy, composed = build_zone_erv_pair(zone_count: 3)
    assert_model_parity(legacy, composed)
    assert_equal(3, composed.getZoneHVACEnergyRecoveryVentilators.size)
  end

  def test_zone_erv_checklist
    _legacy, composed = build_zone_erv_pair
    hx = composed.getHeatExchangerAirToAirSensibleAndLatents.first
    assert_equal('Plate', hx.heatExchangerType)
    assert_in_delta(0.52, composed.getFanOnOffs.first.fanTotalEfficiency, 0.001)
    sizing = composed.getThermalZones.min_by { |z| z.name.get }.sizingZone
    assert(sizing.accountforDedicatedOutdoorAirSystem)
    # supply setpoints derived from the 0.76 sensible effectiveness
    assert_in_delta(OpenStudio.convert(61.6, 'F', 'C').get, sizing.dedicatedOutdoorAirLowSetpointTemperatureforDesign.get, 0.01)
    assert_in_delta(OpenStudio.convert(79.8, 'F', 'C').get, sizing.dedicatedOutdoorAirHighSetpointTemperatureforDesign.get, 0.01)
  end

  def test_zone_erv_forward_translates
    model, zones = model_with_floor_oa_zones(2)
    @composers.zone_erv(model, zones)
    ft = OpenStudio::EnergyPlus::ForwardTranslator.new
    ft.translateModel(model)
    assert_equal(0, ft.errors.size, ft.errors.map(&:logMessage).join("\n"))
  end

  # ---- VRF (condensing unit + per-zone terminals) ----

  def build_vrf_pair(zone_count: 2, **kwargs)
    legacy, legacy_zones = model_with_zones(zone_count)
    composed, composed_zones = model_with_zones(zone_count)
    legacy_hvac.model_add_vrf(legacy, legacy_zones, **kwargs)
    @composers.vrf(composed, composed_zones, **kwargs)
    [legacy, composed]
  end

  def test_vrf_default_parity
    legacy, composed = build_vrf_pair
    assert_model_parity(legacy, composed)
    assert_equal(1, composed.getAirConditionerVariableRefrigerantFlows.size)
    assert_equal(2, composed.getZoneHVACTerminalUnitVariableRefrigerantFlows.size)
  end

  def test_vrf_ventilation_parity
    legacy, composed = build_vrf_pair(ventilation: true)
    assert_model_parity(legacy, composed)
  end

  def test_vrf_multiple_zones_parity
    legacy, composed = build_vrf_pair(zone_count: 4)
    assert_model_parity(legacy, composed)
    assert_equal(4, composed.getZoneHVACTerminalUnitVariableRefrigerantFlows.size)
    # all terminals attach to the single condensing unit
    assert_equal(4, composed.getAirConditionerVariableRefrigerantFlows.first.terminals.size)
  end

  def test_vrf_checklist
    _legacy, composed = build_vrf_pair
    cu = composed.getAirConditionerVariableRefrigerantFlows.first
    assert_equal('2 Zone VRF System', cu.name.get)
    assert_equal('Zone 1', cu.zoneforMasterThermostatLocation.get.name.get)
    fan = composed.getFanOnOffs.find { |f| f.name.get.include?('VRF Unit Cycling Fan') }
    assert_in_delta(300.0, fan.pressureRise, 0.01)
    assert_in_delta(0.6, fan.fanTotalEfficiency, 0.001)
  end

  def test_vrf_returns_empty_array
    # the legacy model_add_vrf never populates its result and returns an empty array
    model, zones = model_with_zones(2)
    assert_equal([], @composers.vrf(model, zones))
  end

  def test_vrf_forward_translates
    model, zones = model_with_zones(2)
    @composers.vrf(model, zones)
    ft = OpenStudio::EnergyPlus::ForwardTranslator.new
    ft.translateModel(model)
    assert_equal(0, ft.errors.size, ft.errors.map(&:logMessage).join("\n"))
  end

  def test_apply_hvac_returns_built_loops
    model = OpenStudio::Model::Model.new
    context = @hvac.apply_hvac(model, {
                                 plant_loop_info: [{
                                   name: 'HW', design_info: { loop_type: 'Heating', supply_temp_f: 180.0, temp_delta_r: 20.0 },
                                   supply_branches: [[{ obj_type: 'BoilerHotWater', eff: 0.9 }]],
                                   controls: [{ spm_type: 'Scheduled', spm_temp_f: 180.0 }]
                                 }]
                               })
    assert(context.plant_loops.key?('HW'), 'apply_hvac exposes the created plant loops by name')
    assert_equal(context.plant_loop('HW'), context.plant_loops['HW'])
  end
  # ---- sizing behaviours this fork carries beyond upstream ----

  # The VAV family autosizes the central heating maximum system air flow ratio unless a number pins it,
  # on both the legacy module and the composer, so parity holds with the fork default.
  def test_vav_family_autosizes_the_central_heating_airflow_ratio
    model, zones = model_with_zones(2)
    chw = add_water_loop(model, 'CHW', 6.7, 6.7)
    loops = [
      @composers.vav_reheat(model, zones, heating_type: 'Electricity', reheat_type: 'Electricity'),
      @composers.pvav(model, zones, electric_reheat: true),
      @composers.vav_pfp_boxes(model, zones, chilled_water_loop: chw),
      @composers.pvav_pfp_boxes(model, zones)
    ]
    loops.each do |air_loop|
      assert(air_loop.sizingSystem.isCentralHeatingMaximumSystemAirFlowRatioAutosized, "#{air_loop.name} should autosize the ratio")
    end
  end

  def test_vav_family_keeps_a_pinned_central_heating_airflow_ratio
    legacy, legacy_zones = model_with_zones(2)
    composed, composed_zones = model_with_zones(2)
    @hvac.model_add_vav_reheat(legacy, legacy_zones, heating_type: 'Electricity', reheat_type: 'Electricity', min_sys_airflow_ratio: 0.3)
    air_loop = @composers.vav_reheat(composed, composed_zones, heating_type: 'Electricity', reheat_type: 'Electricity', min_sys_airflow_ratio: 0.3)
    assert_model_parity(legacy, composed)
    refute(air_loop.sizingSystem.isCentralHeatingMaximumSystemAirFlowRatioAutosized)
    assert_in_delta(0.3, air_loop.sizingSystem.centralHeatingMaximumSystemAirFlowRatio.get, 1e-9)
    pvav = @composers.pvav(composed, composed_zones, electric_reheat: true, min_sys_airflow_ratio: 0.3)
    assert_in_delta(0.3, pvav.sizingSystem.centralHeatingMaximumSystemAirFlowRatio.get, 1e-9)
  end

  # A zone served by its own furnace gets the air flow floor the fork added to the legacy builder.
  def test_furnace_zones_get_the_residential_air_flow_floor
    legacy, composed = build_furnace_pair(heating: true, cooling: true)
    [legacy, composed].each do |model|
      model.getThermalZones.each do |zone|
        assert_equal('DesignDayWithLimit', zone.sizingZone.coolingDesignAirFlowMethod, "#{zone.name}: cooling method")
        assert_equal('DesignDay', zone.sizingZone.heatingDesignAirFlowMethod, "#{zone.name}: heating method is left alone")
      end
    end
  end
end
