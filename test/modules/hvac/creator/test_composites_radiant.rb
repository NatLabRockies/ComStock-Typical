require_relative '../../../helpers/minitest_helper'

class TestHVACCreatorCompositesRadiant < Minitest::Test
  def setup
    @model = OpenStudio::Model::Model.new
    @ctx = OpenstudioStandards::HVAC::BuildContext.new(@model)
    @factory = OpenstudioStandards::HVAC::ComponentFactory
    @plant = OpenstudioStandards::HVAC::PlantLoopBuilder
    build_loops
  end

  def build_loops
    @plant.build({ name: 'CHW Loop', design_info: { loop_type: 'Cooling', supply_temp_f: 44.0 },
                   supply_inlet_components: [{ obj_type: 'PumpVariableSpeed', pump_head_fth2o: 60.0 }],
                   supply_branches: [[{ obj_type: 'DistrictCooling' }]],
                   controls: [{ spm_type: 'Scheduled', spm_temp_f: 44.0 }] }, @ctx)
    @plant.build({ name: 'HW Loop', design_info: { loop_type: 'Heating', supply_temp_f: 120.0 },
                   supply_inlet_components: [{ obj_type: 'PumpVariableSpeed', pump_head_fth2o: 60.0 }],
                   supply_branches: [[{ obj_type: 'BoilerHotWater', eff: 0.9 }]],
                   controls: [{ spm_type: 'Scheduled', spm_temp_f: 120.0 }] }, @ctx)
  end

  def test_unitary_changeover_bypass_assigns_subcomponents
    unitary = @factory.build({ obj_type: 'AirLoopHVACUnitaryHeatCoolVAVChangeoverBypass',
                               priority_ctrl_mode: 'CoolingPriority',
                               fan_operation: { placement: 'BlowThrough' },
                               components: [
                                 { obj_type: 'FanConstantVolume' },
                                 { obj_type: 'CoilCoolingDXSingleSpeed', rated_cop: 3.5 },
                                 { obj_type: 'CoilHeatingGas', eff_percent: 80.0 }
                               ] }, @ctx).to_AirLoopHVACUnitaryHeatCoolVAVChangeoverBypass.get
    assert(unitary.supplyAirFan.to_FanConstantVolume.is_initialized)
    assert(unitary.coolingCoil.to_CoilCoolingDXSingleSpeed.is_initialized)
    assert(unitary.heatingCoil.to_CoilHeatingGas.is_initialized)
    assert_equal('CoolingPriority', unitary.priorityControlMode)
  end

  def test_hx_assist_wraps_water_coil_and_hx
    system = @factory.build({ obj_type: 'CoilSystemCoolingWaterHXAssist',
                              coil_inputs: { plant_loop_name: 'CHW Loop', ewt_f: 44.0 },
                              hx_inputs: { hx_type: 'Rotary' } }, @ctx).to_CoilSystemCoolingWaterHeatExchangerAssisted.get
    assert(system.coolingCoil.to_CoilCoolingWater.is_initialized)
    assert(system.heatExchanger.to_HeatExchangerAirToAirSensibleAndLatent.is_initialized)
    # the inner cooling coil is connected to the chilled water loop demand
    assert(@ctx.plant_loop('CHW Loop').demandComponents.any? { |c| c.to_CoilCoolingWater.is_initialized })
  end

  def test_low_temperature_radiant_electric
    radiant = @factory.build({ obj_type: 'ZoneHVACLowTemperatureRadiantElectric',
                               surface_type: 'Floors', max_elec_w: 1000.0 }, @ctx)
    assert(radiant.to_ZoneHVACLowTemperatureRadiantElectric.is_initialized)
  end

  def test_low_temp_radiant_var_flow_connects_coils
    radiant = @factory.build({ obj_type: 'ZoneHVACLowTempRadiantVarFlow',
                               hot_water_loop_name: 'HW Loop', chilled_water_loop_name: 'CHW Loop',
                               radiant_type: 'floor' }, @ctx)
    assert(radiant.to_ZoneHVACLowTempRadiantVarFlow.is_initialized)
    assert(@ctx.plant_loop('HW Loop').demandComponents.any? { |c| c.to_CoilHeatingLowTempRadiantVarFlow.is_initialized })
    assert(@ctx.plant_loop('CHW Loop').demandComponents.any? { |c| c.to_CoilCoolingLowTempRadiantVarFlow.is_initialized })
  end

  # The full field set the per-zone radiant loop of model_add_low_temp_radiant configures (named
  # coils with a control throttling range, hydronic tubing / circuit layout, and control types). The
  # broader method's climate-zone materials, internal-source constructions, and EMS control
  # strategies remain the shared imperative helpers' responsibility.
  def test_low_temp_radiant_var_flow_full_field_set
    radiant = @factory.build({ obj_type: 'ZoneHVACLowTempRadiantVarFlow', name: 'Zone Radiant Loop',
                               hot_water_loop_name: 'HW Loop', chilled_water_loop_name: 'CHW Loop', radiant_type: 'floor',
                               heating_coil_name: 'Zone Radiant Loop Heating Coil', cooling_coil_name: 'Zone Radiant Loop Cooling Coil',
                               throttling_range_r: 4.0, tubing_inside_diameter_m: 0.015875,
                               number_of_circuits: 'CalculateFromCircuitLength', circuit_length_m: 106.7,
                               temperature_control_type: 'SurfaceFaceTemperature', setpoint_control_type: 'ZeroFlowPower' }, @ctx)
    radiant = radiant.to_ZoneHVACLowTempRadiantVarFlow.get
    assert_equal('Floors', radiant.radiantSurfaceType.get)
    assert_in_delta(0.015875, radiant.hydronicTubingInsideDiameter, 1e-6)
    assert_equal('CalculateFromCircuitLength', radiant.numberofCircuits)
    assert_in_delta(106.7, radiant.circuitLength, 0.01)
    assert_equal('SurfaceFaceTemperature', radiant.temperatureControlType)
    assert_equal('ZeroFlowPower', radiant.setpointControlType)
    heating_coil = radiant.heatingCoil.get.to_CoilHeatingLowTempRadiantVarFlow.get
    assert_equal('Zone Radiant Loop Heating Coil', heating_coil.name.get)
    assert_in_delta(OpenStudio.convert(4.0, 'R', 'K').get, heating_coil.heatingControlThrottlingRange, 0.001)
    cooling_coil = radiant.coolingCoil.get.to_CoilCoolingLowTempRadiantVarFlow.get
    assert_in_delta(OpenStudio.convert(4.0, 'R', 'K').get, cooling_coil.coolingControlThrottlingRange, 0.001)
  end

  # The simplified default path (no extra fields) still creates its own control-temperature schedules.
  def test_low_temp_radiant_var_flow_simplified_defaults
    @factory.build({ obj_type: 'ZoneHVACLowTempRadiantVarFlow', hot_water_loop_name: 'HW Loop',
                     chilled_water_loop_name: 'CHW Loop', radiant_type: 'floor' }, @ctx)
    assert(@model.getScheduleRulesetByName('Radiant Heating Control Temp').is_initialized)
    assert(@model.getScheduleRulesetByName('Radiant Cooling Control Temp').is_initialized)
  end
end
