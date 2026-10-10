require_relative '../helpers/minitest_helper'

# A zone served by its own residential furnace and central AC, or central air source heat
# pump, is sized with a cooling air flow floor so a zone with no design load still gives the
# unit an air flow. A 2026-09 small hotel had an interior, ground-contact restroom with zero
# design heating and cooling load on a "Residential AC with residential forced air furnace"
# loop; EnergyPlus stopped with "Unable to determine fan air flow rate".
class TestResidentialAirFlowFloor < Minitest::Test
  def setup
    @std = Standard.build('90.1-2013')
  end

  def zone_with_space(model, x0)
    polygon = OpenStudio::Point3dVector.new
    [[x0, 0.0], [x0, 6.0], [x0 + 6.0, 6.0], [x0 + 6.0, 0.0]].each { |x, y| polygon << OpenStudio::Point3d.new(x, y, 0.0) }
    space = OpenStudio::Model::Space.fromFloorPrint(polygon, 3.0, model).get
    zone = OpenStudio::Model::ThermalZone.new(model)
    space.setThermalZone(zone)
    heating = OpenStudio::Model::ScheduleConstant.new(model)
    heating.setValue(21.0)
    cooling = OpenStudio::Model::ScheduleConstant.new(model)
    cooling.setValue(24.0)
    thermostat = OpenStudio::Model::ThermostatSetpointDualSetpoint.new(model)
    thermostat.setHeatingSetpointTemperatureSchedule(heating)
    thermostat.setCoolingSetpointTemperatureSchedule(cooling)
    zone.setThermostatSetpointDualSetpoint(thermostat)
    zone
  end

  def test_the_floor_sets_the_cooling_method_and_leaves_the_rest
    model = OpenStudio::Model::Model.new
    zone = zone_with_space(model, 0.0)
    sizing = zone.sizingZone
    sizing.setCoolingMinimumAirFlowperZoneFloorArea(0.001)
    assert_equal('DesignDay', sizing.coolingDesignAirFlowMethod)
    OpenstudioStandards::HVAC.thermal_zone_apply_residential_air_flow_floor(zone)
    assert_equal('DesignDayWithLimit', sizing.coolingDesignAirFlowMethod)
    assert_equal('DesignDay', sizing.heatingDesignAirFlowMethod, 'the heating method is a cap, not a floor, and is left alone')
    assert_in_delta(0.001, sizing.coolingMinimumAirFlowperZoneFloorArea, 1e-9, 'the minimum the zone carries is kept')
  end

  def test_residential_furnace_and_heat_pump_zones_get_the_floor
    { 'Residential AC with residential forced air furnace' => 'Central Heating and AC', 'Residential air source heat pump' => nil }.each do |system, _name|
      model = OpenStudio::Model::Model.new
      zones = [zone_with_space(model, 0.0), zone_with_space(model, 10.0)]
      ok = if system.include?('furnace')
             OpenstudioStandards::HVAC.model_add_furnace_central_ac(model, zones, heating: true, cooling: true, ventilation: false)
           else
             OpenstudioStandards::HVAC.model_add_central_air_source_heat_pump(model, zones, heating: true, cooling: true, ventilation: false)
           end
      refute(ok.is_a?(FalseClass), "#{system} was not added")
      assert_equal(2, model.getAirLoopHVACs.size, "#{system}: one loop per zone")
      zones.each do |zone|
        assert_equal('DesignDayWithLimit', zone.sizingZone.coolingDesignAirFlowMethod, "#{system}: #{zone.name}")
        assert_equal('DesignDay', zone.sizingZone.heatingDesignAirFlowMethod, "#{system}: #{zone.name}")
        assert_operator(zone.sizingZone.coolingMinimumAirFlowperZoneFloorArea, :>, 0.0, "#{system}: the default minimum gives the floor its value")
      end
    end
  end

  def test_a_packaged_single_zone_unit_is_not_changed
    model = OpenStudio::Model::Model.new
    zones = [zone_with_space(model, 0.0)]
    OpenstudioStandards::HVAC.model_add_psz_ac(model, zones, cooling_type: 'Single Speed DX AC', heating_type: 'Gas', fan_location: 'DrawThrough', fan_type: 'ConstantVolume')
    assert_equal('DesignDay', zones.first.sizingZone.coolingDesignAirFlowMethod)
  end
end
