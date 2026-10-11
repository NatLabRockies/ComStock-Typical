require_relative '../../../helpers/minitest_helper'

class TestHVACCreatorPlantDemand < Minitest::Test
  def setup
    @model = OpenStudio::Model::Model.new
    @ctx = OpenstudioStandards::HVAC::BuildContext.new(@model)
    @factory = OpenstudioStandards::HVAC::ComponentFactory
    @plant = OpenstudioStandards::HVAC::PlantLoopBuilder
    @air = OpenstudioStandards::HVAC::AirLoopBuilder
    @zones = OpenstudioStandards::HVAC::ZoneBuilder
    @zone = OpenStudio::Model::ThermalZone.new(@model)
    @zone.setName('Zone 1')
  end

  def chw_loop_spec
    { name: 'CHW Loop', design_info: { loop_type: 'Cooling', supply_temp_f: 44.0 },
      supply_inlet_components: [{ obj_type: 'PumpVariableSpeed', pump_head_fth2o: 60.0 }],
      supply_branches: [[{ obj_type: 'DistrictCooling', name: 'District Clg' }]],
      controls: [{ spm_type: 'Scheduled', spm_temp_f: 44.0 }] }
  end

  def hw_loop_spec
    { name: 'HW Loop', design_info: { loop_type: 'Heating', supply_temp_f: 180.0 },
      supply_inlet_components: [{ obj_type: 'PumpConstantSpeed', pump_head_fth2o: 60.0 }],
      supply_branches: [[{ obj_type: 'BoilerHotWater', eff: 0.9 }]],
      controls: [{ spm_type: 'Scheduled', spm_temp_f: 180.0 }] }
  end

  # a cooling water coil placed on an air loop should be connected on BOTH the air supply side
  # and the chilled water loop demand side — the same coil object on both loops.
  def test_cooling_water_coil_connects_air_and_plant
    @plant.build(chw_loop_spec, @ctx)
    air_loop = @air.build({ name: 'AHU',
                            supply_components: [
                              { obj_type: 'CoilCoolingWater', name: 'CW Coil', plant_loop_name: 'CHW Loop', ewt_f: 44.0 },
                              { obj_type: 'FanVariableVolume', name: 'SF' }
                            ],
                            controls: [{ spm_type: 'Scheduled', spm_temp_f: 55.0 }] }, @ctx)
    chw = @ctx.plant_loop('CHW Loop')
    on_air = air_loop.supplyComponents.find { |c| c.to_CoilCoolingWater.is_initialized }
    on_plant = chw.demandComponents.find { |c| c.to_CoilCoolingWater.is_initialized }
    refute_nil(on_air, 'cooling coil should be on the air loop supply')
    refute_nil(on_plant, 'cooling coil should be on the chilled water loop demand')
    assert_equal(on_air.handle.to_s, on_plant.handle.to_s, 'same coil object on both loops')
  end

  # a hot water reheat coil inside a VAV terminal should be connected to the hot water loop demand.
  def test_hot_water_reheat_coil_connects_to_plant
    @plant.build(hw_loop_spec, @ctx)
    @air.build({ name: 'AHU', supply_components: [{ obj_type: 'FanVariableVolume', name: 'SF' }],
                 controls: [{ spm_type: 'Scheduled', spm_temp_f: 55.0 }] }, @ctx)
    @zones.build({ zone_name: 'Zone 1', air_loop_name: 'AHU',
                   air_terminal_info: { air_terminal_type: 'AirTerminalSingleDuctVAVReheat',
                                        reheat: { coil_info: { obj_type: 'CoilHeatingWater', plant_loop_name: 'HW Loop', ewt_f: 180.0 } } } }, @ctx)
    hw = @ctx.plant_loop('HW Loop')
    assert(hw.demandComponents.any? { |c| c.to_CoilHeatingWater.is_initialized })
  end

  # a water coil in a unitary system on an air loop should reach the plant demand too.
  def test_unitary_water_cooling_coil_connects_to_plant
    @plant.build(chw_loop_spec, @ctx)
    @air.build({ name: 'AHU',
                 supply_components: [
                   { obj_type: 'AirLoopHVACUnitarySystem',
                     components: [
                       { obj_type: 'FanOnOff' },
                       { obj_type: 'CoilCoolingWater', plant_loop_name: 'CHW Loop' },
                       { obj_type: 'CoilHeatingElectric' }
                     ] }
                 ],
                 controls: [{ spm_type: 'Scheduled', spm_temp_f: 55.0 }] }, @ctx)
    chw = @ctx.plant_loop('CHW Loop')
    assert(chw.demandComponents.any? { |c| c.to_CoilCoolingWater.is_initialized })
  end

  def test_apply_hvac_water_coil_end_to_end
    spec = { plant_loop_info: [chw_loop_spec],
             air_system_info: [{ name: 'AHU',
                                 supply_components: [
                                   { obj_type: 'CoilCoolingWater', plant_loop_name: 'CHW Loop' },
                                   { obj_type: 'FanVariableVolume', name: 'SF' }
                                 ],
                                 controls: [{ spm_type: 'Scheduled', spm_temp_f: 55.0 }] }] }
    OpenstudioStandards::HVAC.apply_hvac(@model, spec)
    chw = @model.getPlantLoopByName('CHW Loop').get
    assert(chw.demandComponents.any? { |c| c.to_CoilCoolingWater.is_initialized })
  end

  def test_water_coil_missing_plant_raises
    assert_raises(ArgumentError) do
      @factory.build({ obj_type: 'CoilCoolingWater', plant_loop_name: 'Nonexistent' }, @ctx)
    end
  end

  # A hot-water coil that names only its loop takes the loop's design exit temperature as its
  # entering water temperature, and that less the loop design difference as its leaving temperature.
  def test_heating_water_coil_water_temperatures_default_from_loop
    @plant.build(hw_loop_spec.merge(design_info: { loop_type: 'Heating', supply_temp_f: 180.0, temp_delta_r: 30.0 }), @ctx)
    coil = @factory.build({ obj_type: 'CoilHeatingWater', plant_loop_name: 'HW Loop' }, @ctx).to_CoilHeatingWater.get
    assert_in_delta(OpenStudio.convert(180.0, 'F', 'C').get, coil.ratedInletWaterTemperature, 0.01)
    assert_in_delta(OpenStudio.convert(150.0, 'F', 'C').get, coil.ratedOutletWaterTemperature, 0.01)
  end

  def test_heating_water_coil_leaving_temperature_defaults_from_given_entering
    @plant.build(hw_loop_spec.merge(design_info: { loop_type: 'Heating', supply_temp_f: 180.0, temp_delta_r: 30.0 }), @ctx)
    coil = @factory.build({ obj_type: 'CoilHeatingWater', plant_loop_name: 'HW Loop', ewt_f: 170.0 }, @ctx).to_CoilHeatingWater.get
    assert_in_delta(OpenStudio.convert(170.0, 'F', 'C').get, coil.ratedInletWaterTemperature, 0.01)
    assert_in_delta(OpenStudio.convert(140.0, 'F', 'C').get, coil.ratedOutletWaterTemperature, 0.01)
  end

  def test_heating_water_coil_capacity_and_ua
    @plant.build(hw_loop_spec, @ctx)
    coil = @factory.build({ obj_type: 'CoilHeatingWater', plant_loop_name: 'HW Loop', capacity_btuh: 100_000.0, ua_ip: 1000.0 }, @ctx).to_CoilHeatingWater.get
    assert_in_delta(29_307.1, coil.ratedCapacity.get, 1.0)
    assert_in_delta(527.5, coil.uFactorTimesAreaValue.get, 0.5)
  end

  def test_heating_water_coil_autosizes_capacity_when_not_given
    @plant.build(hw_loop_spec, @ctx)
    coil = @factory.build({ obj_type: 'CoilHeatingWater', plant_loop_name: 'HW Loop' }, @ctx).to_CoilHeatingWater.get
    assert(coil.isRatedCapacityAutosized)
  end

  def test_district_cooling_autosizes_without_capacity
    district = @factory.build({ obj_type: 'DistrictCooling' }, @ctx)
    assert(district.to_DistrictCooling.is_initialized)
    assert(district.isNominalCapacityAutosized)
  end

  def test_district_cooling_capacity
    district = @factory.build({ obj_type: 'DistrictCooling', capacity_btuh: 100_000.0 }, @ctx)
    assert_in_delta(29_307.1, district.nominalCapacity.get, 1.0)
  end
end
