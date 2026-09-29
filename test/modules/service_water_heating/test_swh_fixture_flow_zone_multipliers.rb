require_relative '../../helpers/minitest_helper'

# A space in a zone with a multiplier stands for that many identical spaces, and EnergyPlus
# multiplies each WaterUse:Equipment draw by the zone multiplier. The fixture must therefore be
# sized on the space's own floor area, once. Sizing it on floor area times multiplier, as the
# code used to, counted the multiplier twice: a mid-story restroom in a zone with a multiplier of
# 10 drew ten times the water the space type data says, and the heater sizing, which weights each
# fixture by its multiplier, compounded that to a hundred.
class TestSwhFixtureFlowZoneMultipliers < Minitest::Test
  def setup
    @swh = OpenstudioStandards::ServiceWaterHeating
  end

  # two 10 m x 10 m spaces of one space type, one in a zone with the given multiplier. A typical
  # (all-level) name resolves on its own; a prototype name needs its building type as well.
  def two_spaces(model, standards_space_type, multiplier:, building_type: nil)
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setName(standards_space_type)
    space_type.setStandardsSpaceType(standards_space_type)
    space_type.setStandardsBuildingType(building_type) unless building_type.nil?
    polygon = OpenStudio::Point3dVector.new
    polygon << OpenStudio::Point3d.new(0, 0, 0)
    polygon << OpenStudio::Point3d.new(0, 10, 0)
    polygon << OpenStudio::Point3d.new(10, 10, 0)
    polygon << OpenStudio::Point3d.new(10, 0, 0)
    { 'single' => 1, 'multiplied' => multiplier }.map do |label, mult|
      space = OpenStudio::Model::Space.fromFloorPrint(polygon, 3.0, model).get
      space.setName("#{standards_space_type} #{label}")
      space.setSpaceType(space_type)
      zone = OpenStudio::Model::ThermalZone.new(model)
      zone.setName("Zone #{space.name}")
      zone.setMultiplier(mult)
      space.setThermalZone(zone)
      space
    end
  end

  def gph(water_use_equipment)
    OpenStudio.convert(water_use_equipment.waterUseEquipmentDefinition.peakFlowRate, 'm^3/s', 'gal/hr').get
  end

  def test_shared_fixture_flow_is_the_space_area_times_the_rate_regardless_of_multiplier
    model = OpenStudio::Model::Model.new
    single, multiplied = two_spaces(model, 'restroom', multiplier: 10)
    loops = @swh.create_typical_service_water_heating(model)
    refute_empty(loops)

    # the office restroom record: one entry at 0.02 gph/ft2 (it used to carry three)
    area_ft2 = OpenStudio.convert(single.floorArea, 'm^2', 'ft^2').get
    assert_equal(1, single.waterUseEquipment.size, 'one draw per restroom space')
    assert_in_epsilon(0.02 * area_ft2, gph(single.waterUseEquipment.first), 0.01)

    assert_equal(1, multiplied.waterUseEquipment.size)
    assert_in_epsilon(gph(single.waterUseEquipment.first), gph(multiplied.waterUseEquipment.first), 1e-6,
                      'the multiplied space carries the same per-space draw; EnergyPlus supplies the copies')

    # the shared heater is sized on 1 + 10 spaces' worth of draw
    heater = model.getWaterHeaterMixeds.find { |wh| wh.name.to_s !~ /booster/i }
    refute_nil(heater)
    single_only = OpenStudio::Model::Model.new
    two_spaces(single_only, 'restroom', multiplier: 1)
    @swh.create_typical_service_water_heating(single_only)
    two_singles = single_only.getWaterHeaterMixeds.first
    assert_in_epsilon(11.0 / 2.0, heater.heaterMaximumCapacity.get / two_singles.heaterMaximumCapacity.get, 0.05,
                      'heater sizing weights each fixture by its zone multiplier')
  end

  def test_dedicated_loop_fixture_flow_ignores_the_multiplier_but_its_heaters_do_not
    model = OpenStudio::Model::Model.new
    single, multiplied = two_spaces(model, 'retail', multiplier: 4)
    loops = @swh.create_typical_service_water_heating(model)
    assert_equal(2, loops.size, 'one dedicated loop per retail space')

    assert_in_epsilon(gph(single.waterUseEquipment.first), gph(multiplied.waterUseEquipment.first), 1e-6)

    # one WaterHeater:Mixed stands for N point-of-use heaters: totals scale, component_quantity counts
    assert_equal([1, 4], heater_quantities(loops).sort, 'the loop serving four copies carries four heaters')
    assert_in_epsilon(4.0, heater_capacity_ratio(loops), 0.01)
  end

  # component_quantity of the single water heater object on each loop
  def heater_quantities(loops)
    loops.map do |loop|
      heater = loop.supplyComponents.find { |c| c.to_WaterHeaterMixed.is_initialized }.to_WaterHeaterMixed.get
      quantity = heater.additionalProperties.getFeatureAsInteger('component_quantity')
      quantity.is_initialized ? quantity.get : 1
    end
  end

  # largest over smallest loop heater capacity
  def heater_capacity_ratio(loops)
    capacities = loops.map { |loop| loop.supplyComponents.find { |c| c.to_WaterHeaterMixed.is_initialized }.to_WaterHeaterMixed.get.heaterMaximumCapacity.get }
    capacities.max / capacities.min
  end

  def test_one_per_unit_flow_counts_units_in_the_space_only
    model = OpenStudio::Model::Model.new
    # the apartment record has no all-level mapping yet, so it resolves through the prototype key
    single, multiplied = two_spaces(model, 'Apartment', multiplier: 3, building_type: 'MidriseApartment')
    [single, multiplied].each { |space| space.additionalProperties.setFeature('num_units', 2) }
    loops = @swh.create_typical_service_water_heating(model)
    assert_equal(2, loops.size)

    # the record is a per-unit flow of 3.48 gph: two units in each physical space, copies left to EnergyPlus
    assert_in_epsilon(2 * 3.48, gph(single.waterUseEquipment.first), 0.01)
    assert_in_epsilon(gph(single.waterUseEquipment.first), gph(multiplied.waterUseEquipment.first), 1e-6)
    assert_equal([2, 6], heater_quantities(loops).sort, 'two units times three copies')
    assert_in_epsilon(3.0, heater_capacity_ratio(loops), 0.01)
  end
end
