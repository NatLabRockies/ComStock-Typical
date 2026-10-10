require_relative '../../../helpers/minitest_helper'

class TestHVACCreatorDXMultiSpeedCoils < Minitest::Test
  def setup
    @model = OpenStudio::Model::Model.new
    @ctx = OpenstudioStandards::HVAC::BuildContext.new(@model)
    @factory = OpenstudioStandards::HVAC::ComponentFactory
  end

  def biquad(name)
    { type: 'Biquadratic', coefficients: [1.0, 0.0, 0.0, 0.0, 0.0, 0.0], name: name }
  end

  def quad
    { type: 'Quadratic', coefficients: [1.0, 0.0, 0.0] }
  end

  # ---- variable speed cooling ----

  def test_variable_speed_builds_speeds
    coil = @factory.build({ obj_type: 'CoilCoolingDXVariableSpeed',
                            rated_total_capacity_w: 10_000.0, rated_airflow_m3s: 0.5, nominal_speed_level: 2,
                            speeds: [
                              { cop: 3.0, capacity_frac: 0.5, flow_frac: 0.5, shr: 0.7,
                                curves: { cap_ft: biquad('VS CapFT'), cap_ff: quad, eir_ft: biquad('VS EIRFT'), eir_ff: quad } },
                              { cop: 3.5, capacity_w: 10_000.0, flow_m3s: 0.5, shr: 0.7 }
                            ] }, @ctx)
    vs = coil.to_CoilCoolingDXVariableSpeed.get
    assert_equal(2, vs.speeds.size)
    assert_equal(2, vs.nominalSpeedLevel)
    assert_in_delta(3.0, vs.speeds[0].referenceUnitGrossRatedCoolingCOP, 0.001)
    assert_equal('VS CapFT', vs.speeds[0].totalCoolingCapacityFunctionofTemperatureCurve.name.get)
  end

  def test_variable_speed_capacity_fraction_scaling
    coil = @factory.build({ obj_type: 'CoilCoolingDXVariableSpeed', rated_total_capacity_w: 10_000.0,
                            speeds: [{ cop: 3.0, capacity_frac: 0.4 }] }, @ctx)
    vs = coil.to_CoilCoolingDXVariableSpeed.get
    assert_in_delta(4000.0, vs.speeds[0].referenceUnitGrossRatedTotalCoolingCapacity, 1.0)
  end

  # ---- multi speed cooling ----

  def test_multi_speed_cooling_builds_stages
    coil = @factory.build({ obj_type: 'CoilCoolingDXMultiSpeed', condenser_type: 'AirCooled',
                            stages: [
                              { capacity_w: 5000.0, cop: 3.0, flow_m3s: 0.25, shr: 0.7 },
                              { capacity_w: 10_000.0, cop: 3.2, flow_m3s: 0.5, shr: 0.7,
                                curves: { cap_ft: biquad('MS CapFT') } }
                            ] }, @ctx)
    ms = coil.to_CoilCoolingDXMultiSpeed.get
    assert_equal(2, ms.stages.size)
    assert_equal('AirCooled', ms.condenserType)
    assert_in_delta(10_000.0, ms.stages[1].grossRatedTotalCoolingCapacity.get, 1.0)
    assert_equal('MS CapFT', ms.stages[1].totalCoolingCapacityFunctionofTemperatureCurve.name.get)
  end

  # ---- multi speed heating ----

  def test_multi_speed_heating_builds_stages_and_defrost
    coil = @factory.build({ obj_type: 'CoilHeatingDXMultiSpeed',
                            defrost: { strategy: 'ReverseCycle', control: 'OnDemand', max_oat_defrost_f: 40.0 },
                            crankcase: { heater_w: 50.0, max_oat_f: 55.0 },
                            stages: [
                              { capacity_w: 5000.0, cop: 3.0, flow_m3s: 0.25 },
                              { capacity_w: 10_000.0, cop: 3.4, flow_m3s: 0.5 }
                            ] }, @ctx)
    heating = coil.to_CoilHeatingDXMultiSpeed.get
    assert_equal(2, heating.stages.size)
    assert_equal('ReverseCycle', heating.defrostStrategy)
    assert_in_delta(10_000.0, heating.stages[1].grossRatedHeatingCapacity.get, 1.0)
  end

  # ---- schema key coverage ----

  def test_schema_keys_allowed
    vs_keys = @factory.allowed_keys_for('CoilCoolingDXVariableSpeed')
    assert_includes(vs_keys, 'speeds')
    assert_includes(vs_keys, 'plf_curve')
    heat_keys = @factory.allowed_keys_for('CoilHeatingDXMultiSpeed')
    assert_includes(heat_keys, 'stages')
    assert_includes(heat_keys, 'defrost')
    assert_includes(heat_keys, 'crankcase')
  end
end
