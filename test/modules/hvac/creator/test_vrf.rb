require_relative '../../../helpers/minitest_helper'

class TestHVACCreatorVRF < Minitest::Test
  def setup
    @model = OpenStudio::Model::Model.new
    @ctx = OpenstudioStandards::HVAC::BuildContext.new(@model)
    @vrf = OpenstudioStandards::HVAC::VrfBuilder
    @factory = OpenstudioStandards::HVAC::ComponentFactory
    @hvac = OpenstudioStandards::HVAC
    @zone1 = OpenStudio::Model::ThermalZone.new(@model)
    @zone1.setName('Zone 1')
    @zone2 = OpenStudio::Model::ThermalZone.new(@model)
    @zone2.setName('Zone 2')
  end

  def test_condensing_unit_built_and_registered
    cu = @vrf.build({ name: 'VRF-1', cooling_cop: 4.0, heating_cop: 4.2, condenser_type: 'AirCooled' }, @ctx)
    assert(cu.to_AirConditionerVariableRefrigerantFlow.is_initialized)
    assert_equal('VRF-1', cu.name.get)
    assert_equal(cu, @ctx.vrf_cu('VRF-1'))
  end

  def test_terminal_attaches_to_condensing_unit
    @vrf.build({ name: 'VRF-1', cooling_cop: 4.0, heating_cop: 4.2 }, @ctx)
    terminal = @factory.build({ obj_type: 'ZoneHVACTerminalUnitVariableRefrigerantFlow',
                                cu_name: 'VRF-1', sa_cfm: 300.0 }, @ctx)
    assert(terminal.to_ZoneHVACTerminalUnitVariableRefrigerantFlow.is_initialized)
    cu = @ctx.vrf_cu('VRF-1')
    assert_equal(1, cu.terminals.size)
    assert_equal(terminal.handle.to_s, cu.terminals.first.handle.to_s)
  end

  def test_terminal_missing_cu_raises
    assert_raises(ArgumentError) do
      @factory.build({ obj_type: 'ZoneHVACTerminalUnitVariableRefrigerantFlow', cu_name: 'Nope' }, @ctx)
    end
  end

  def test_apply_hvac_vrf_end_to_end
    spec = {
      custom_system_type: 'Factory VRF',
      vrf_info: [{ name: 'VRF-1', cooling_cop: 4.0, heating_cop: 4.2, heat_recovery: true }],
      zone_info: [
        { zone_name: 'Zone 1',
          zone_equipment: [{ obj_type: 'ZoneHVACTerminalUnitVariableRefrigerantFlow', cu_name: 'VRF-1', sa_cfm: 300.0 }] },
        { zone_name: 'Zone 2',
          zone_equipment: [{ obj_type: 'ZoneHVACTerminalUnitVariableRefrigerantFlow', cu_name: 'VRF-1', sa_cfm: 250.0 }] }
      ]
    }
    @hvac.apply_hvac(@model, spec)
    cus = @model.getAirConditionerVariableRefrigerantFlows
    assert_equal(1, cus.size)
    assert_equal(2, cus.first.terminals.size)
    # each terminal is on its thermal zone
    terminals = @model.getZoneHVACTerminalUnitVariableRefrigerantFlows
    assert_equal(2, terminals.size)
    assert(terminals.all? { |t| t.thermalZone.is_initialized })
  end
end
