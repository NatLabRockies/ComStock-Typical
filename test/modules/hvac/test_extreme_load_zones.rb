require_relative '../../helpers/minitest_helper'

# Data center and other extreme-load zones leave the building's main CBECS system and get
# their own: a CRAC when the building cools with DX, a CRAH on the chilled water plant when
# it has one, and a packaged single-zone unit for extreme loads that are not data centers.
# Leg D put every office data center on the office's packaged VAV system; on PVAV systems
# the zone read as heated-only and every sizing run failed, and once it did not, the office
# ran with thousands of unmet cooling hours.
class TestExtremeLoadZones < Minitest::Test
  def setup
    @hvac = OpenstudioStandards::HVAC
    @std = Standard.build('90.1-2013')
  end

  # clockwise 10 x 10 m print at x offset, which Space.fromFloorPrint requires
  def print(x0)
    polygon = OpenStudio::Point3dVector.new
    [[x0, 0.0], [x0, 10.0], [x0 + 10.0, 10.0], [x0 + 10.0, 0.0]].each { |x, y| polygon << OpenStudio::Point3d.new(x, y, 0.0) }
    polygon
  end

  # a zone with one space of the named standards space type carrying the given equipment
  # density, on a dual setpoint thermostat so the CBECS assignment sees it as heated and cooled
  def add_zone(model, name, space_type_name, w_per_ft2, x0)
    space = OpenStudio::Model::Space.fromFloorPrint(print(x0), 3.0, model).get
    space.setName(name)
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setName(space_type_name)
    space_type.setStandardsSpaceType(space_type_name)
    space.setSpaceType(space_type)
    if w_per_ft2 > 0.0
      definition = OpenStudio::Model::ElectricEquipmentDefinition.new(model)
      definition.setWattsperSpaceFloorArea(OpenStudio.convert(w_per_ft2, 'W/ft^2', 'W/m^2').get)
      equip = OpenStudio::Model::ElectricEquipment.new(definition)
      equip.setSpace(space)
    end
    zone = OpenStudio::Model::ThermalZone.new(model)
    zone.setName("Zone #{name}")
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

  def office_with_data_center(model)
    model.getClimateZones.setClimateZone('ASHRAE', '5A')
    office = add_zone(model, 'Office', 'office', 1.0, 0.0)
    data_center = add_zone(model, 'Data Center', 'datacenter/high ite', 100.0, 20.0)
    [office, data_center]
  end

  def loop_of(zone)
    zone.airLoopHVAC.is_initialized ? zone.airLoopHVAC.get : nil
  end

  def test_density_and_data_center_classification
    model = OpenStudio::Model::Model.new
    office, data_center = office_with_data_center(model)
    assert_in_delta(1.0, @hvac.thermal_zone_electric_equipment_w_per_ft2(office), 0.01)
    assert_in_delta(100.0, @hvac.thermal_zone_electric_equipment_w_per_ft2(data_center), 0.01)
    refute(@hvac.thermal_zone_data_center?(office))
    assert(@hvac.thermal_zone_data_center?(data_center))
    # ComStock's low-ITE office data center at 40 W/ft2 counts too
    low = add_zone(model, 'Low ITE', 'datacenter/low ite', 40.0, 40.0)
    assert(@hvac.thermal_zone_data_center?(low))
    # a school computer lab is a classroom with computers, not a data center
    lab = add_zone(model, 'Computer Lab', 'computer room', 0.24, 60.0)
    refute(@hvac.thermal_zone_data_center?(lab))
    # the prototype names count as well
    proto = add_zone(model, 'Main Data Center', 'Main Data Center', 45.0, 80.0)
    assert(@hvac.thermal_zone_data_center?(proto))

    groups = @hvac.split_extreme_load_zones([office, data_center, low, lab, proto])
    assert_equal([office, lab], groups[:main])
    assert_equal([data_center, low, proto], groups[:data_center])
    assert_empty(groups[:extreme])
  end

  def test_cooling_source_is_read_from_the_system_name
    assert_equal(false, @hvac.cbecs_hvac_cooling_source('PVAV with PFP boxes')[:chilled_water])
    assert_equal(false, @hvac.cbecs_hvac_cooling_source('PSZ-AC with gas coil')[:chilled_water])
    assert_equal(false, @hvac.cbecs_hvac_cooling_source('DOAS with water source heat pumps cooling tower with boiler')[:chilled_water])
    water = @hvac.cbecs_hvac_cooling_source('VAV chiller with PFP boxes')
    assert(water[:chilled_water])
    assert_equal('Electricity', water[:cool_fuel])
    assert_equal('WaterCooled', water[:chilled_water_loop_cooling_type])
    air = @hvac.cbecs_hvac_cooling_source('VAV air-cooled chiller with gas boiler reheat')
    assert_equal('AirCooled', air[:chilled_water_loop_cooling_type])
    district = @hvac.cbecs_hvac_cooling_source('VAV district chilled water with district hot water reheat')
    assert_equal('DistrictCooling', district[:cool_fuel])
  end

  # The leg D case: a large office data center on a packaged VAV system.
  def test_data_center_on_a_pvav_building_gets_a_crac
    model = OpenStudio::Model::Model.new
    office, data_center = office_with_data_center(model)
    assert(@hvac.add_cbecs_hvac_system(model, @std, 'PVAV with PFP boxes', [office, data_center]))

    refute_nil(loop_of(office), 'the office lost its system')
    refute_nil(loop_of(data_center), 'the data center got no system')
    refute_equal(loop_of(office), loop_of(data_center), 'the data center is still on the office system')
    assert_match(/CRAC/, loop_of(data_center).name.to_s)
    dx_on_crac = loop_of(data_center).supplyComponents.any? { |c| c.to_CoilCoolingDXSingleSpeed.is_initialized || c.to_CoilCoolingDXTwoSpeed.is_initialized }
    assert(dx_on_crac, 'a CRAC cools with DX')
    assert_empty(model.getPlantLoops.select { |l| l.name.to_s.include?('Chilled Water') }, 'a DX building gets no chilled water plant')
  end

  def test_data_center_on_a_chiller_building_gets_a_crah_on_the_same_plant
    model = OpenStudio::Model::Model.new
    office, data_center = office_with_data_center(model)
    assert(@hvac.add_cbecs_hvac_system(model, @std, 'VAV chiller with PFP boxes', [office, data_center]))

    refute_equal(loop_of(office), loop_of(data_center))
    assert_match(/CRAH/, loop_of(data_center).name.to_s)
    chw_loops = model.getPlantLoops.select { |l| l.name.to_s == 'Chilled Water Loop' }
    assert_equal(1, chw_loops.size, 'the CRAH reuses the building chilled water loop')
    crah_coil = loop_of(data_center).supplyComponents.find { |c| c.to_CoilCoolingWater.is_initialized }
    refute_nil(crah_coil, 'a CRAH cools with chilled water')
    assert_equal(chw_loops.first, crah_coil.to_CoilCoolingWater.get.plantLoop.get)
  end

  def test_data_center_on_a_district_chilled_water_building_gets_a_crah
    model = OpenStudio::Model::Model.new
    office, data_center = office_with_data_center(model)
    assert(@hvac.add_cbecs_hvac_system(model, @std, 'VAV district chilled water with district hot water reheat', [office, data_center]))
    assert_match(/CRAH/, loop_of(data_center).name.to_s)
    assert_equal(1, model.getPlantLoops.count { |l| l.name.to_s == 'Chilled Water Loop' })
  end

  def test_data_center_on_a_psz_building_gets_a_crac
    model = OpenStudio::Model::Model.new
    office, data_center = office_with_data_center(model)
    assert(@hvac.add_cbecs_hvac_system(model, @std, 'PSZ-AC with gas coil', [office, data_center]))
    assert_match(/PSZ-AC/, loop_of(office).name.to_s)
    assert_match(/CRAC/, loop_of(data_center).name.to_s)
  end

  # The CRAC and CRAH builders leave the zone heating design supply temperature at 55 F, below
  # ComStock's 18 C heating setpoint. With a design heating load that gives EnergyPlus a zone
  # heating air flow in the tens of thousands of kg/s and a coil in the hundreds of megawatts;
  # in the 2026-09 rerun building 3924's zone temperatures overflowed and the run died.
  def test_data_center_zone_heating_sizing_temperature_is_above_the_heating_setpoint
    ['PVAV with PFP boxes', 'VAV chiller with PFP boxes'].each do |system|
      model = OpenStudio::Model::Model.new
      office, data_center = office_with_data_center(model)
      assert(@hvac.add_cbecs_hvac_system(model, @std, system, [office, data_center]))
      sizing = data_center.sizingZone
      assert_equal('SupplyAirTemperature', sizing.zoneHeatingDesignSupplyAirTemperatureInputMethod)
      htg_setpoint_c = 21.0 # the test thermostat; ComStock's data centers use 18 C
      assert_operator(sizing.zoneHeatingDesignSupplyAirTemperature, :>, htg_setpoint_c + 2.0, "#{system}: heating supply must clear the setpoint by the 2 C EnergyPlus check")
      expected = @std.standard_design_sizing_temperatures['zn_htg_dsgn_sup_air_temp_c']
      assert_in_delta(expected, sizing.zoneHeatingDesignSupplyAirTemperature, 1e-6, system)
      # cooling side is untouched: the unit's 55 F supply
      assert_in_delta(OpenStudio.convert(55.0, 'F', 'C').get, sizing.zoneCoolingDesignSupplyAirTemperature, 1e-6, system)
    end
  end

  # An extreme load that is not a data center gets its own packaged unit, not a CRAC.
  def test_other_extreme_loads_get_their_own_packaged_unit
    model = OpenStudio::Model::Model.new
    office, data_center = office_with_data_center(model)
    hot = add_zone(model, 'Process', 'workshop', 60.0, 40.0)
    assert(@hvac.add_cbecs_hvac_system(model, @std, 'PVAV with PFP boxes', [office, data_center, hot]))
    refute_equal(loop_of(office), loop_of(hot))
    refute_match(/CRAC/, loop_of(hot).name.to_s)
    assert_match(/PSZ-AC/, loop_of(hot).name.to_s)
    assert_match(/CRAC/, loop_of(data_center).name.to_s)
  end

  # A building that is nothing but data center still gets served.
  def test_a_building_of_only_data_center_zones_is_served
    model = OpenStudio::Model::Model.new
    model.getClimateZones.setClimateZone('ASHRAE', '5A')
    data_center = add_zone(model, 'Data Center', 'datacenter/high ite', 100.0, 0.0)
    assert(@hvac.add_cbecs_hvac_system(model, @std, 'PVAV with PFP boxes', [data_center]))
    assert_match(/CRAC/, loop_of(data_center).name.to_s)
    assert_empty(model.getAirLoopHVACs.reject { |l| l.name.to_s.include?('CRAC') }, 'no empty main system should be built')
  end

  # An office with no data center is untouched by the split.
  def test_ordinary_buildings_are_unchanged
    model = OpenStudio::Model::Model.new
    model.getClimateZones.setClimateZone('ASHRAE', '5A')
    a = add_zone(model, 'Office A', 'office', 1.0, 0.0)
    b = add_zone(model, 'Office B', 'office', 1.0, 20.0)
    assert(@hvac.add_cbecs_hvac_system(model, @std, 'PVAV with PFP boxes', [a, b]))
    assert_equal(1, model.getAirLoopHVACs.size)
    assert_equal(loop_of(a), loop_of(b))
  end
end
