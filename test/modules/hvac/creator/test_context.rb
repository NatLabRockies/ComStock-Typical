require_relative '../../../helpers/minitest_helper'

class TestHVACCreatorBuildContext < Minitest::Test
  def setup
    @model = OpenStudio::Model::Model.new
    @ctx = OpenstudioStandards::HVAC::BuildContext.new(@model)
  end

  def test_register_and_resolve_plant_loop
    loop = OpenStudio::Model::PlantLoop.new(@model)
    loop.setName('HW Loop')
    @ctx.register_plant_loop('HW Loop', loop)
    assert_equal(loop, @ctx.plant_loop('HW Loop'))
  end

  def test_resolve_plant_loop_from_model_when_not_registered
    loop = OpenStudio::Model::PlantLoop.new(@model)
    loop.setName('Existing Loop')
    # not registered, but present in the model
    assert_equal('Existing Loop', @ctx.plant_loop('Existing Loop').name.get)
  end

  def test_resolve_air_loop
    air = OpenStudio::Model::AirLoopHVAC.new(@model)
    air.setName('AHU 1')
    @ctx.register_air_loop('AHU 1', air)
    assert_equal(air, @ctx.air_loop('AHU 1'))
  end

  def test_missing_plant_loop_raises
    err = assert_raises(ArgumentError) { @ctx.plant_loop('Nope') }
    assert_match(/plant loop 'Nope'/, err.message)
  end

  def test_zone_lookup
    zone = OpenStudio::Model::ThermalZone.new(@model)
    zone.setName('Zone 1')
    assert_equal('Zone 1', @ctx.zone('Zone 1').name.get)
  end

  def test_missing_zone_raises
    assert_raises(ArgumentError) { @ctx.zone('No Zone') }
  end

  def test_schedule_always_on_sentinel
    sch = @ctx.schedule('AlwaysOn')
    assert(sch.is_a?(OpenStudio::Model::Schedule))
  end

  def test_schedule_always_off_sentinel
    sch = @ctx.schedule('AlwaysOff')
    assert(sch.is_a?(OpenStudio::Model::Schedule))
  end

  def test_schedule_existing_by_name
    ruleset = OpenStudio::Model::ScheduleRuleset.new(@model)
    ruleset.setName('My Sched')
    assert_equal('My Sched', @ctx.schedule('My Sched').name.get)
  end

  def test_schedule_missing_raises_without_fallback
    assert_raises(ArgumentError) { @ctx.schedule('Ghost Schedule') }
  end

  def test_schedule_missing_creates_constant_with_fallback
    sch = @ctx.schedule('New Const', constant_value: 21.0, type_limits: 'Temperature')
    assert_equal('New Const', sch.name.get)
  end

  def test_warn_and_error_collected
    @ctx.warn('a warning')
    @ctx.error('an error')
    assert_equal(2, @ctx.messages.size)
    assert_equal('a warning', @ctx.messages.first[:message])
  end

  def test_curve_lookup_by_name
    curve = OpenStudio::Model::CurveBiquadratic.new(@model)
    curve.setName('MyCurve')
    assert_equal('MyCurve', @ctx.curve('MyCurve').name.get)
  end

  def test_curve_missing_raises
    assert_raises(ArgumentError) { @ctx.curve('NoSuchCurve') }
  end
end
