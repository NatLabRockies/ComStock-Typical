require_relative '../../../helpers/minitest_helper'

class TestHVACCreatorComponentFactory < Minitest::Test
  def setup
    @model = OpenStudio::Model::Model.new
    @ctx = OpenstudioStandards::HVAC::BuildContext.new(@model)
    @factory = OpenstudioStandards::HVAC::ComponentFactory
  end

  def test_build_fan_on_off_sets_fields
    fan = @factory.build({ obj_type: 'FanOnOff', name: 'Supply Fan',
                           fan_total_eff: 0.6, pressure_rise_inh2o: 1.0, max_airflow_cfm: 1000.0 }, @ctx)
    assert(fan.to_FanOnOff.is_initialized)
    assert_equal('Supply Fan', fan.name.get)
    assert_in_delta(0.6, fan.fanEfficiency, 0.001)
    assert_in_delta(249.089, fan.pressureRise, 0.1)
    assert_in_delta(0.47195, fan.maximumFlowRate.get, 0.0001)
  end

  def test_fan_preset_resolves_via_typical_fan
    fan = @factory.build({ obj_type: 'FanOnOff', name: 'AHU Fan', preset: 'Packaged_RTU_SZ_AC_CAV_OnOff_Fan' }, @ctx)
    assert(fan.to_FanOnOff.is_initialized, 'the preset selects the packaged fan class')
    fan = fan.to_FanOnOff.get
    assert_equal('AHU Fan', fan.name.get)
    reference = OpenstudioStandards::HVAC.create_typical_fan(@model, 'Packaged_RTU_SZ_AC_CAV_OnOff_Fan', fan_name: 'Ref').to_FanOnOff.get
    assert_in_delta(reference.fanEfficiency, fan.fanEfficiency, 1e-6)
    assert_in_delta(reference.pressureRise, fan.pressureRise, 1e-3)
    assert_in_delta(reference.motorEfficiency, fan.motorEfficiency, 1e-6)
  end

  def test_unknown_fan_preset_raises
    assert_raises(ArgumentError) { @factory.build({ obj_type: 'FanOnOff', preset: 'Nonexistent_Fan' }, @ctx) }
  end

  def test_build_fan_variable_volume
    fan = @factory.build({ obj_type: 'FanVariableVolume', pressure_rise_pa: 500.0 }, @ctx)
    assert(fan.to_FanVariableVolume.is_initialized)
    assert_in_delta(500.0, fan.pressureRise, 0.1)
  end

  def test_build_coil_heating_gas_percent_efficiency
    coil = @factory.build({ obj_type: 'CoilHeatingGas', eff_percent: 80.0 }, @ctx)
    assert(coil.to_CoilHeatingGas.is_initialized)
    assert_in_delta(0.80, coil.gasBurnerEfficiency, 0.001)
  end

  def test_build_coil_heating_electric_capacity
    coil = @factory.build({ obj_type: 'CoilHeatingElectric', capacity_btuh: 34_121.0 }, @ctx)
    assert(coil.to_CoilHeatingElectric.is_initialized)
    assert_in_delta(10_000.0, coil.nominalCapacity.get, 5.0)
  end

  def test_schedule_name_applied
    ruleset = OpenStudio::Model::ScheduleRuleset.new(@model)
    ruleset.setName('Fan Avail')
    fan = @factory.build({ obj_type: 'FanConstantVolume', schedule_name: 'Fan Avail' }, @ctx)
    assert_equal('Fan Avail', fan.availabilitySchedule.name.get)
  end

  def test_unknown_obj_type_raises
    assert_raises(ArgumentError) { @factory.build({ obj_type: 'NotAThing' }, @ctx) }
  end

  def test_missing_obj_type_raises
    assert_raises(ArgumentError) { @factory.build({ name: 'x' }, @ctx) }
  end

  def test_unknown_key_warns
    @factory.build({ obj_type: 'FanOnOff', bogus_key: 1 }, @ctx)
    assert(@ctx.messages.any? { |m| m[:message].include?("unrecognized key 'bogus_key'") })
  end

  def test_known_keys_do_not_warn
    @factory.build({ obj_type: 'FanOnOff', fan_total_eff: 0.5, pressure_rise_pa: 250.0, name: 'ok' }, @ctx)
    assert(@ctx.messages.none? { |m| m[:message].include?('unrecognized key') })
  end

  def test_preset_warns_for_unresolved_component
    # Fans resolve presets through the packaged data; other components still warn (not yet resolved).
    @factory.build({ obj_type: 'BoilerHotWater', preset: 'Typical' }, @ctx)
    assert(@ctx.messages.any? { |m| m[:message].include?('preset') })
  end

  def test_string_keys_accepted
    fan = @factory.build({ 'obj_type' => 'FanOnOff', 'name' => 'StrFan' }, @ctx)
    assert_equal('StrFan', fan.name.get)
  end

  def test_allowed_keys_index_includes_base_and_branch
    keys = @factory.allowed_keys_for('FanVariableVolume')
    assert_includes(keys, 'obj_type')       # base
    assert_includes(keys, 'schedule_name')  # base
    assert_includes(keys, 'fan_total_eff')  # fanCommon (mixed into fanBasicObj)
    assert_includes(keys, 'curve_type')     # fanBasicObj
  end
end
