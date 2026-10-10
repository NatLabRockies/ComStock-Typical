require_relative '../../../helpers/minitest_helper'

class TestHVACCreatorChilledWaterPlant < Minitest::Test
  def setup
    @model = OpenStudio::Model::Model.new
    @ctx = OpenstudioStandards::HVAC::BuildContext.new(@model)
    @plant = OpenstudioStandards::HVAC::PlantLoopBuilder
    @factory = OpenstudioStandards::HVAC::ComponentFactory
  end

  def cw_loop_spec
    { name: 'CW Loop', design_info: { loop_type: 'Condenser', supply_temp_f: 85.0 },
      supply_inlet_components: [{ obj_type: 'PumpVariableSpeed', pump_head_fth2o: 60.0 }],
      supply_branches: [[{ obj_type: 'CoolingTowerVariableSpeed', name: 'Tower' }]],
      controls: [{ spm_type: 'Scheduled', spm_temp_f: 85.0 }] }
  end

  def chw_loop_spec
    { name: 'CHW Loop', design_info: { loop_type: 'Cooling', supply_temp_f: 44.0 },
      supply_inlet_components: [{ obj_type: 'PumpVariableSpeed', pump_head_fth2o: 60.0 }],
      supply_branches: [[{ obj_type: 'ChillerElectricEIR', name: 'Chiller 1', cop: 5.5,
                           condenser_loop_name: 'CW Loop', leaving_chw_temp_f: 44.0 }]],
      controls: [{ spm_type: 'Scheduled', spm_temp_f: 44.0 }] }
  end

  # condenser loop must be built before the chilled water loop that references it
  def build_plants
    @plant.build(cw_loop_spec, @ctx)
    @plant.build(chw_loop_spec, @ctx)
  end

  def test_chiller_on_chilled_water_supply
    build_plants
    chw = @ctx.plant_loop('CHW Loop')
    assert(chw.supplyComponents.any? { |c| c.to_ChillerElectricEIR.is_initialized })
  end

  def test_chiller_on_condenser_demand
    build_plants
    cw = @ctx.plant_loop('CW Loop')
    assert(cw.demandComponents.any? { |c| c.to_ChillerElectricEIR.is_initialized })
  end

  def test_same_chiller_object_on_both_loops
    build_plants
    chw = @ctx.plant_loop('CHW Loop')
    cw = @ctx.plant_loop('CW Loop')
    on_chw = chw.supplyComponents.find { |c| c.to_ChillerElectricEIR.is_initialized }
    on_cw = cw.demandComponents.find { |c| c.to_ChillerElectricEIR.is_initialized }
    assert_equal(on_chw.handle.to_s, on_cw.handle.to_s)
  end

  def test_chiller_condenser_type_and_cop
    build_plants
    chiller = @model.getChillerElectricEIRs.first
    assert_equal('WaterCooled', chiller.condenserType)
    assert_in_delta(5.5, chiller.referenceCOP, 0.001)
  end

  def test_cooling_tower_on_condenser_supply
    build_plants
    cw = @ctx.plant_loop('CW Loop')
    assert(cw.supplyComponents.any? { |c| c.to_CoolingTowerVariableSpeed.is_initialized })
  end

  def test_air_cooled_chiller_defaults_without_condenser_loop
    chiller = @factory.build({ obj_type: 'ChillerElectricEIR', cop: 3.0 }, @ctx)
    assert_equal('AirCooled', chiller.condenserType)
  end

  def test_chiller_schema_keys_allowed
    keys = @factory.allowed_keys_for('ChillerElectricEIR')
    assert_includes(keys, 'cop')
    assert_includes(keys, 'condenser_type')
    assert_includes(keys, 'condenser_loop_name')
  end
end
