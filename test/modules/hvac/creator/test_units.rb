require_relative '../../../helpers/minitest_helper'

# The schema states every physical quantity in both IP and SI, and the two are meant to be
# interchangeable: a spec written in IP and the same spec written in SI must build the same model.
# test_quantities checks the conversion in isolation; these check it end to end, through the factory,
# on the fields a spec author is most likely to reach for.
class TestHVACCreatorUnits < Minitest::Test
  def setup
    @hvac = OpenstudioStandards::HVAC
  end

  def f_to_c(value)
    OpenStudio.convert(value, 'F', 'C').get
  end

  def r_to_k(value)
    OpenStudio.convert(value, 'R', 'K').get
  end

  # The same plant loop, once in IP and once in SI.
  def ip_spec
    {
      plant_loop_info: [{
        name: 'Hot Water Loop',
        design_info: { loop_type: 'Heating', supply_temp_f: 180.0, temp_delta_r: 20.0 },
        min_loop_temp_f: 50.0,
        max_loop_temp_f: 210.0,
        supply_inlet_components: [{ obj_type: 'PumpVariableSpeed', name: 'HW Pump', pump_head_fth2o: 60.0 }],
        supply_branches: [[{ obj_type: 'BoilerHotWater', name: 'Boiler', capacity_btuh: 500_000.0 }]],
        controls: [{ spm_type: 'Scheduled', name: 'HW SPM', spm_temp_f: 180.0 }]
      }]
    }
  end

  def si_spec
    {
      plant_loop_info: [{
        name: 'Hot Water Loop',
        design_info: { loop_type: 'Heating', supply_temp_c: f_to_c(180.0), temp_delta_k: r_to_k(20.0) },
        min_loop_temp_c: f_to_c(50.0),
        max_loop_temp_c: f_to_c(210.0),
        supply_inlet_components: [{ obj_type: 'PumpVariableSpeed', name: 'HW Pump',
                                    pump_head_pa: OpenStudio.convert(60.0, 'ftH_{2}O', 'Pa').get }],
        supply_branches: [[{ obj_type: 'BoilerHotWater', name: 'Boiler',
                             capacity_w: OpenStudio.convert(500_000.0, 'Btu/h', 'W').get }]],
        controls: [{ spm_type: 'Scheduled', name: 'HW SPM', spm_temp_c: f_to_c(180.0) }]
      }]
    }
  end

  def build(spec)
    model = OpenStudio::Model::Model.new
    @hvac.apply_hvac(model, spec)
    model
  end

  def test_ip_and_si_specs_build_the_same_model
    ip = build(ip_spec)
    si = build(si_spec)

    ip_loop = ip.getPlantLoopByName('Hot Water Loop').get
    si_loop = si.getPlantLoopByName('Hot Water Loop').get
    assert_in_delta(ip_loop.sizingPlant.designLoopExitTemperature, si_loop.sizingPlant.designLoopExitTemperature, 1.0e-6)
    assert_in_delta(ip_loop.sizingPlant.loopDesignTemperatureDifference, si_loop.sizingPlant.loopDesignTemperatureDifference, 1.0e-6)
    assert_in_delta(ip_loop.minimumLoopTemperature, si_loop.minimumLoopTemperature, 1.0e-6)
    assert_in_delta(ip_loop.maximumLoopTemperature, si_loop.maximumLoopTemperature, 1.0e-6)

    assert_in_delta(ip.getPumpVariableSpeeds.first.ratedPumpHead, si.getPumpVariableSpeeds.first.ratedPumpHead, 1.0e-3)
    assert_in_delta(ip.getBoilerHotWaters.first.nominalCapacity.get, si.getBoilerHotWaters.first.nominalCapacity.get, 1.0e-3)
  end

  # Object counts and names match too, so neither form quietly builds something extra.
  def test_ip_and_si_specs_produce_the_same_objects
    ip_types = build(ip_spec).getModelObjects.map { |o| o.iddObjectType.valueName }.tally
    si_types = build(si_spec).getModelObjects.map { |o| o.iddObjectType.valueName }.tally
    assert_equal(ip_types, si_types)
  end

  # Giving both units for one quantity is fine when they agree...
  def test_agreeing_unit_pair_is_accepted
    spec = ip_spec
    spec[:plant_loop_info][0][:design_info][:supply_temp_c] = f_to_c(180.0)
    model = build(spec)
    assert_in_delta(f_to_c(180.0), model.getPlantLoops.first.sizingPlant.designLoopExitTemperature, 1.0e-6)
  end

  # ...and an error when they do not: silently preferring one would build a model the author did not
  # ask for.
  def test_contradictory_unit_pair_raises
    spec = ip_spec
    spec[:plant_loop_info][0][:design_info][:supply_temp_c] = f_to_c(120.0)
    error = assert_raises(ArgumentError) { build(spec) }
    assert_match(/supply_temp/, error.message)
  end

  def test_contradictory_unit_pair_raises_for_a_component_field
    spec = ip_spec
    spec[:plant_loop_info][0][:supply_branches][0][0][:capacity_w] = 1.0
    assert_raises(ArgumentError) { build(spec) }
  end
end
