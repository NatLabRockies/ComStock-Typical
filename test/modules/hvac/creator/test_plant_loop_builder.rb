require_relative '../../../helpers/minitest_helper'

class TestHVACCreatorPlantLoopBuilder < Minitest::Test
  def setup
    @model = OpenStudio::Model::Model.new
    @ctx = OpenstudioStandards::HVAC::BuildContext.new(@model)
    @builder = OpenstudioStandards::HVAC::PlantLoopBuilder
    @spm = OpenstudioStandards::HVAC::SetpointManagerFactory
  end

  def hw_loop_spec
    {
      name: 'HW Loop',
      design_info: { loop_type: 'Heating', supply_temp_f: 180.0, temp_delta_r: 20.0 },
      supply_inlet_components: [
        { obj_type: 'PumpVariableSpeed', name: 'HW Pump', pump_head_fth2o: 60.0, vsd_control_type: 'Riding Curve' }
      ],
      supply_branches: [
        [{ obj_type: 'BoilerHotWater', name: 'Boiler 1', eff: 0.9, capacity_btuh: 500_000.0 }]
      ],
      controls: [{ spm_type: 'Scheduled', spm_temp_f: 180.0 }],
      min_loop_temp_f: 50.0
    }
  end

  def test_builds_named_loop
    loop = @builder.build(hw_loop_spec, @ctx)
    assert(loop.to_PlantLoop.is_initialized)
    assert_equal('HW Loop', loop.name.get)
  end

  def test_sizing_plant_fields
    loop = @builder.build(hw_loop_spec, @ctx)
    sizing = loop.sizingPlant
    assert_equal('Heating', sizing.loopType)
    assert_in_delta(82.22, sizing.designLoopExitTemperature, 0.05)
    assert_in_delta(11.11, sizing.loopDesignTemperatureDifference, 0.05)
  end

  def test_min_loop_temperature
    loop = @builder.build(hw_loop_spec, @ctx)
    assert_in_delta(10.0, loop.minimumLoopTemperature, 0.05)
  end

  def test_pump_on_supply_inlet
    loop = @builder.build(hw_loop_spec, @ctx)
    inlet_component = loop.supplyInletNode.outletModelObject.get
    assert(inlet_component.to_PumpVariableSpeed.is_initialized, 'pump should sit at the supply inlet')
    pump = inlet_component.to_PumpVariableSpeed.get
    assert_in_delta(3.2485, pump.coefficient2ofthePartLoadPerformanceCurve, 0.001) # Riding Curve coefficients
  end

  def test_boiler_on_supply_branch
    loop = @builder.build(hw_loop_spec, @ctx)
    boilers = loop.supplyComponents.select { |c| c.to_BoilerHotWater.is_initialized }
    assert_equal(1, boilers.size)
    assert_in_delta(0.9, boilers.first.to_BoilerHotWater.get.nominalThermalEfficiency, 0.001)
  end

  def test_setpoint_manager_on_supply_outlet
    loop = @builder.build(hw_loop_spec, @ctx)
    managers = loop.supplyOutletNode.setpointManagers.select { |m| m.to_SetpointManagerScheduled.is_initialized }
    assert_equal(1, managers.size)
  end

  def test_loop_registered_in_context
    loop = @builder.build(hw_loop_spec, @ctx)
    assert_equal(loop, @ctx.plant_loop('HW Loop'))
  end

  def test_two_parallel_branches
    spec = hw_loop_spec
    spec[:supply_branches] = [
      [{ obj_type: 'BoilerHotWater', name: 'B1', eff: 0.9 }],
      [{ obj_type: 'BoilerHotWater', name: 'B2', eff: 0.8 }]
    ]
    loop = @builder.build(spec, @ctx)
    boilers = loop.supplyComponents.select { |c| c.to_BoilerHotWater.is_initialized }
    assert_equal(2, boilers.size)
  end

  def test_accepts_string_keys
    loop = @builder.build(JSON.parse(hw_loop_spec.to_json), @ctx)
    assert_equal('HW Loop', loop.name.get)
    assert_equal('Heating', loop.sizingPlant.loopType)
  end

  def test_spm_factory_scheduled_control_variable
    spm = @spm.build({ spm_type: 'Scheduled', spm_temp_f: 55.0 }, @ctx)
    assert(spm.to_SetpointManagerScheduled.is_initialized)
    assert_equal('Temperature', spm.controlVariable)
  end

  def test_spm_factory_unknown_type_raises
    assert_raises(ArgumentError) { @spm.build({ spm_type: 'Nonexistent' }, @ctx) }
  end

  def test_spm_node_override_by_component_name
    spec = hw_loop_spec
    spec[:controls] = [{ spm_type: 'Scheduled', spm_temp_f: 180.0, spm_node: 'Boiler 1' }]
    loop = @builder.build(spec, @ctx)
    boiler = loop.supplyComponents.find { |c| c.to_BoilerHotWater.is_initialized }
    boiler_outlet = boiler.to_BoilerHotWater.get.outletModelObject.get.to_Node.get
    assert_equal(1, boiler_outlet.setpointManagers.size, 'setpoint manager should sit on the named boiler outlet')
    assert_equal(0, loop.supplyOutletNode.setpointManagers.size, 'setpoint manager should not remain on the supply outlet')
  end

  def test_spm_node_override_by_idd_type
    spec = hw_loop_spec
    spec[:controls] = [{ spm_type: 'Scheduled', spm_temp_f: 180.0, spm_node: 'BoilerHotWater' }]
    loop = @builder.build(spec, @ctx)
    boiler = loop.supplyComponents.find { |c| c.to_BoilerHotWater.is_initialized }
    boiler_outlet = boiler.to_BoilerHotWater.get.outletModelObject.get.to_Node.get
    assert_equal(1, boiler_outlet.setpointManagers.size)
  end

  def test_spm_node_ambiguous_type_raises
    spec = hw_loop_spec
    spec[:supply_branches] = [
      [{ obj_type: 'BoilerHotWater', name: 'B1', eff: 0.9 }],
      [{ obj_type: 'BoilerHotWater', name: 'B2', eff: 0.8 }]
    ]
    spec[:controls] = [{ spm_type: 'Scheduled', spm_temp_f: 180.0, spm_node: 'BoilerHotWater' }]
    assert_raises(ArgumentError) { @builder.build(spec, @ctx) }
  end

  def test_spm_node_unmatched_falls_back_to_default
    spec = hw_loop_spec
    spec[:controls] = [{ spm_type: 'Scheduled', spm_temp_f: 180.0, spm_node: 'No Such Component' }]
    loop = @builder.build(spec, @ctx)
    assert_equal(1, loop.supplyOutletNode.setpointManagers.size, 'an unmatched spm_node falls back to the supply outlet')
    assert(@ctx.messages.any? { |m| m[:message].include?('matched no component') })
  end

  def ground_hx_loop_spec
    {
      name: 'Ground HX Loop',
      design_info: { loop_type: 'Heating', supply_temp_f: 75.0, temp_delta_r: 10.0 },
      ground_hx_loop: true,
      supply_inlet_components: [{ obj_type: 'PumpConstantSpeed', name: 'GHX Pump', pump_head_fth2o: 60.0 }],
      supply_branches: [[{ obj_type: 'PlantComponentTemperatureSource', name: 'Ground HX', temp_spec_type: 'Constant', source_temp_c: 12.0 }]],
      controls: [{ spm_type: 'Scheduled', spm_temp_f: 75.0 }]
    }
  end

  def test_ground_hx_installs_ems
    loop = @builder.build(ground_hx_loop_spec, @ctx)
    source = loop.supplyComponents.find { |c| c.to_PlantComponentTemperatureSource.is_initialized }.to_PlantComponentTemperatureSource.get
    assert_equal('Scheduled', source.temperatureSpecificationType)
    assert(source.sourceTemperatureSchedule.is_initialized, 'temperature source should be driven by a schedule')
    assert(source.sourceTemperatureSchedule.get.to_ScheduleConstant.is_initialized)
    assert_equal(1, @model.getEnergyManagementSystemSensors.size)
    assert_equal(1, @model.getEnergyManagementSystemActuators.size)
    assert_equal(1, @model.getEnergyManagementSystemPrograms.size)
    assert_equal(1, @model.getEnergyManagementSystemProgramCallingManagers.size)
    assert_equal(loop.supplyInletNode.handle.to_s, @model.getEnergyManagementSystemSensors.first.keyName)
  end

  def test_ground_hx_reset_slope_intercept
    slope, intercept = @builder.ground_hx_reset(min_inlet_temp_c: 10.0, max_inlet_temp_c: 30.0, min_outlet_temp_c: 10.0, max_outlet_temp_c: 20.0)
    assert_in_delta(0.5, slope, 0.001)
    assert_in_delta(5.0, intercept, 0.001)
  end

  def test_ground_hx_without_source_warns
    spec = ground_hx_loop_spec
    spec[:supply_branches] = [[{ obj_type: 'BoilerHotWater', name: 'B1', eff: 0.9 }]]
    @builder.build(spec, @ctx)
    assert_equal(0, @model.getEnergyManagementSystemPrograms.size)
    assert(@ctx.messages.any? { |m| m[:message].include?('no PlantComponentTemperatureSource') })
  end

  def primary_secondary_spec(interconnection)
    {
      name: 'CHW Primary',
      design_info: { loop_type: 'Cooling', supply_temp_f: 44.0, temp_delta_r: 10.0 },
      supply_inlet_components: [{ obj_type: 'PumpVariableSpeed', name: 'Primary Pump', pump_head_fth2o: 15.0 }],
      supply_branches: [[{ obj_type: 'ChillerElectricEIR', name: 'Chiller 1', cop: 5.5 }]],
      controls: [{ spm_type: 'Scheduled', spm_temp_f: 44.0 }],
      secondary_loop: {
        name: 'CHW Secondary',
        design_info: { loop_type: 'Cooling', supply_temp_f: 44.0, temp_delta_r: 10.0 },
        supply_inlet_components: [{ obj_type: 'PumpVariableSpeed', name: 'Secondary Pump', pump_head_fth2o: 45.0 }],
        controls: [{ spm_type: 'Scheduled', spm_temp_f: 44.0 }],
        interconnection: interconnection
      }
    }
  end

  def test_secondary_loop_heat_exchanger_join
    primary = @builder.build(primary_secondary_spec('type' => 'heat_exchanger'), @ctx)
    secondary = @ctx.plant_loop('CHW Secondary')
    refute_nil(secondary)
    hx_on_secondary_supply = secondary.supplyComponents.any? { |c| c.to_HeatExchangerFluidToFluid.is_initialized }
    hx_on_primary_demand = primary.demandComponents.any? { |c| c.to_HeatExchangerFluidToFluid.is_initialized }
    assert(hx_on_secondary_supply, 'heat exchanger should sit on the secondary supply side')
    assert(hx_on_primary_demand, 'heat exchanger should sit on the primary demand side')
  end

  def test_secondary_loop_common_pipe_join
    primary = @builder.build(primary_secondary_spec('type' => 'common_pipe'), @ctx)
    assert_equal('CommonPipe', primary.commonPipeSimulation)
    refute_nil(@ctx.plant_loop('CHW Secondary'))
  end
end
