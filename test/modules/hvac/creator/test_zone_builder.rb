require_relative '../../../helpers/minitest_helper'

class TestHVACCreatorZoneBuilder < Minitest::Test
  def setup
    @model = OpenStudio::Model::Model.new
    @ctx = OpenstudioStandards::HVAC::BuildContext.new(@model)
    @zones = OpenstudioStandards::HVAC::ZoneBuilder
    @air = OpenstudioStandards::HVAC::AirLoopBuilder
    @zone = OpenStudio::Model::ThermalZone.new(@model)
    @zone.setName('Zone 1')
  end

  def simple_air_loop
    @air.build({ name: 'AHU',
                 supply_components: [{ obj_type: 'FanConstantVolume', name: 'SF' }],
                 controls: [{ spm_type: 'Scheduled', spm_temp_f: 55.0 }] }, @ctx)
  end

  def test_no_reheat_terminal_attaches_zone_to_air_loop
    air_loop = simple_air_loop
    @zones.build({ zone_name: 'Zone 1', air_loop_name: 'AHU',
                   air_terminal_info: { air_terminal_type: 'AirTerminalSingleDuctConstantVolumeNoReheat',
                                        max_airflow_cfm: 500.0 } }, @ctx)
    assert(@zone.airLoopHVAC.is_initialized)
    assert_equal(air_loop, @zone.airLoopHVAC.get)
  end

  def test_vav_reheat_terminal_builds_reheat_coil
    simple_air_loop
    @zones.build({ zone_name: 'Zone 1', air_loop_name: 'AHU',
                   air_terminal_info: { air_terminal_type: 'AirTerminalSingleDuctVAVReheat',
                                        vav: { min_flow_frac: 0.3 },
                                        reheat: { coil_info: { obj_type: 'CoilHeatingElectric' } } } }, @ctx)
    terminals = @model.getAirTerminalSingleDuctVAVReheats
    assert_equal(1, terminals.size)
    terminal = terminals.first
    assert(terminal.reheatCoil.to_CoilHeatingElectric.is_initialized)
    assert_in_delta(0.3, terminal.constantMinimumAirFlowFraction.get, 0.001)
  end

  def test_reheat_terminal_without_coil_raises
    simple_air_loop
    assert_raises(ArgumentError) do
      @zones.build({ zone_name: 'Zone 1', air_loop_name: 'AHU',
                     air_terminal_info: { air_terminal_type: 'AirTerminalSingleDuctVAVReheat' } }, @ctx)
    end
  end

  def test_unsupported_terminal_raises
    simple_air_loop
    assert_raises(ArgumentError) do
      @zones.build({ zone_name: 'Zone 1', air_loop_name: 'AHU',
                     air_terminal_info: { air_terminal_type: 'AirTerminalSingleDuctConstantVolumeChilledBeam' } }, @ctx)
    end
  end

  def test_zone_equipment_added_with_priority
    @zones.build({ zone_name: 'Zone 1',
                   zone_equipment: [{ obj_type: 'ZoneHVACBaseboardConvectiveElectric',
                                      equipment_list_position: { heat_priority: 1 } }] }, @ctx)
    baseboards = @model.getZoneHVACBaseboardConvectiveElectrics
    assert_equal(1, baseboards.size)
    assert(baseboards.first.thermalZone.is_initialized)
    assert_equal('Zone 1', baseboards.first.thermalZone.get.name.get)
    # heat priority 1 => first in the zone heating order
    assert_equal(baseboards.first.handle.to_s, @zone.equipmentInHeatingOrder.first.handle.to_s)
  end

  def test_zone_sizing_supply_air_temps
    @zones.build({ zone_name: 'Zone 1',
                   zone_sizing: { clg_dsgn_sup_air_temp_f: 55.0, htg_dsgn_sup_air_temp_f: 104.0 } }, @ctx)
    sizing = @zone.sizingZone
    assert_in_delta(12.78, sizing.zoneCoolingDesignSupplyAirTemperature, 0.05)
    assert_in_delta(40.0, sizing.zoneHeatingDesignSupplyAirTemperature, 0.05)
  end

  def test_string_keys_accepted
    simple_air_loop
    @zones.build(JSON.parse({ zone_name: 'Zone 1', air_loop_name: 'AHU',
                              air_terminal_info: { air_terminal_type: 'AirTerminalSingleDuctConstantVolumeNoReheat' } }.to_json), @ctx)
    assert(@zone.airLoopHVAC.is_initialized)
  end
end
