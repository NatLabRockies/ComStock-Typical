require_relative '../../../helpers/minitest_helper'

class TestHVACCreatorZoneHVACEquipment < Minitest::Test
  def setup
    @model = OpenStudio::Model::Model.new
    @ctx = OpenstudioStandards::HVAC::BuildContext.new(@model)
    @factory = OpenstudioStandards::HVAC::ComponentFactory
    @plant = OpenstudioStandards::HVAC::PlantLoopBuilder
    @zones = OpenstudioStandards::HVAC::ZoneBuilder
    @zone = OpenStudio::Model::ThermalZone.new(@model)
    @zone.setName('Zone 1')
    build_loops
  end

  def build_loops
    @plant.build({ name: 'CHW Loop', design_info: { loop_type: 'Cooling', supply_temp_f: 44.0 },
                   supply_inlet_components: [{ obj_type: 'PumpVariableSpeed', pump_head_fth2o: 60.0 }],
                   supply_branches: [[{ obj_type: 'DistrictCooling' }]],
                   controls: [{ spm_type: 'Scheduled', spm_temp_f: 44.0 }] }, @ctx)
    @plant.build({ name: 'HW Loop', design_info: { loop_type: 'Heating', supply_temp_f: 180.0 },
                   supply_inlet_components: [{ obj_type: 'PumpVariableSpeed', pump_head_fth2o: 60.0 }],
                   supply_branches: [[{ obj_type: 'BoilerHotWater', eff: 0.9 }]],
                   controls: [{ spm_type: 'Scheduled', spm_temp_f: 180.0 }] }, @ctx)
  end

  def test_four_pipe_fan_coil_water_coils
    fcu = @factory.build({ obj_type: 'ZoneHVACFourPipeFanCoil',
                           chilled_water_loop_name: 'CHW Loop', hot_water_loop_name: 'HW Loop',
                           capacity_ctrl_method: 'CyclingFan' }, @ctx).to_ZoneHVACFourPipeFanCoil.get
    assert(fcu.coolingCoil.to_CoilCoolingWater.is_initialized)
    assert(fcu.heatingCoil.to_CoilHeatingWater.is_initialized)
    assert_equal('CyclingFan', fcu.capacityControlMethod)
    assert(@ctx.plant_loop('CHW Loop').demandComponents.any? { |c| c.to_CoilCoolingWater.is_initialized })
    assert(@ctx.plant_loop('HW Loop').demandComponents.any? { |c| c.to_CoilHeatingWater.is_initialized })
  end

  def test_four_pipe_fan_coil_electric_heat_without_hot_water
    fcu = @factory.build({ obj_type: 'ZoneHVACFourPipeFanCoil', chilled_water_loop_name: 'CHW Loop' }, @ctx).to_ZoneHVACFourPipeFanCoil.get
    assert(fcu.heatingCoil.to_CoilHeatingElectric.is_initialized)
  end

  def test_baseboard_convective_water
    bb = @factory.build({ obj_type: 'ZoneHVACBaseboardConvectiveWater', hot_water_loop_name: 'HW Loop' }, @ctx)
    assert(bb.to_ZoneHVACBaseboardConvectiveWater.is_initialized)
    assert(@ctx.plant_loop('HW Loop').demandComponents.any? { |c| c.to_CoilHeatingWaterBaseboard.is_initialized })
  end

  def test_unit_heater_electric
    uh = @factory.build({ obj_type: 'ZoneHVACUnitHeater', heating_type: 'Electricity', control_type: 'OnOff' }, @ctx).to_ZoneHVACUnitHeater.get
    assert(uh.heatingCoil.to_CoilHeatingElectric.is_initialized)
    assert_equal('OnOff', uh.fanControlType)
  end

  def test_unit_heater_hot_water
    uh = @factory.build({ obj_type: 'ZoneHVACUnitHeater', heating_type: 'Water', hot_water_loop_name: 'HW Loop' }, @ctx).to_ZoneHVACUnitHeater.get
    assert(uh.heatingCoil.to_CoilHeatingWater.is_initialized)
  end

  # A hot water loop alone means hot-water heat; the fuel need not be repeated.
  def test_unit_heater_hot_water_inferred_from_loop
    uh = @factory.build({ obj_type: 'ZoneHVACUnitHeater', hot_water_loop_name: 'HW Loop' }, @ctx).to_ZoneHVACUnitHeater.get
    assert(uh.heatingCoil.to_CoilHeatingWater.is_initialized)
    assert(@ctx.plant_loop('HW Loop').demandComponents.any? { |c| c.to_CoilHeatingWater.is_initialized })
  end

  def test_unit_heater_water_without_loop_raises
    error = assert_raises(ArgumentError) do
      @factory.build({ obj_type: 'ZoneHVACUnitHeater', name: 'UH', heating_type: 'Water' }, @ctx)
    end
    assert_match(/hot_water_loop_name/, error.message)
  end

  def test_unit_heater_synthesized_fan_takes_pressure_rise_and_airflow
    uh = @factory.build({ obj_type: 'ZoneHVACUnitHeater', hot_water_loop_name: 'HW Loop',
                          fan_pressure_rise_inh2o: 0.2, max_airflow_cfm: 500.0 }, @ctx).to_ZoneHVACUnitHeater.get
    fan = uh.supplyAirFan.to_FanConstantVolume.get
    assert_in_delta(OpenStudio.convert(0.2, 'inH_{2}O', 'Pa').get, fan.pressureRise, 0.1)
    expected_flow = OpenStudio.convert(500.0, 'cfm', 'm^3/s').get
    assert_in_delta(expected_flow, fan.maximumFlowRate.get, 1e-6)
    assert_in_delta(expected_flow, uh.maximumSupplyAirFlowRate.get, 1e-6)
  end

  def test_unit_heater_autosizes_airflow_when_not_given
    uh = @factory.build({ obj_type: 'ZoneHVACUnitHeater', heating_type: 'Electricity' }, @ctx).to_ZoneHVACUnitHeater.get
    assert(uh.isMaximumSupplyAirFlowRateAutosized)
  end

  def test_ptac_hot_water_heat_inferred_from_loop
    ptac = @factory.build({ obj_type: 'ZoneHVACPackagedTerminalAirConditioner', hot_water_loop_name: 'HW Loop', fan_type: 'Cycling' }, @ctx).to_ZoneHVACPackagedTerminalAirConditioner.get
    assert(ptac.heatingCoil.to_CoilHeatingWater.is_initialized)
  end

  def test_ptac_gas_heat
    ptac = @factory.build({ obj_type: 'ZoneHVACPackagedTerminalAirConditioner', heating_type: 'Gas', fan_type: 'Cycling' }, @ctx).to_ZoneHVACPackagedTerminalAirConditioner.get
    assert(ptac.coolingCoil.to_CoilCoolingDXSingleSpeed.is_initialized)
    assert(ptac.heatingCoil.to_CoilHeatingGas.is_initialized)
  end

  def test_added_to_zone_via_zone_builder
    @zones.build({ zone_name: 'Zone 1',
                   zone_equipment: [{ obj_type: 'ZoneHVACFourPipeFanCoil',
                                      chilled_water_loop_name: 'CHW Loop', hot_water_loop_name: 'HW Loop' }] }, @ctx)
    fcus = @model.getZoneHVACFourPipeFanCoils
    assert_equal(1, fcus.size)
    assert(fcus.first.thermalZone.is_initialized)
    assert_equal('Zone 1', fcus.first.thermalZone.get.name.get)
  end
end
