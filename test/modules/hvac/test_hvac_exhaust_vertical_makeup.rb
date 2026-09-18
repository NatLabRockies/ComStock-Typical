require_relative '../../helpers/minitest_helper'

# Makeup air for a kitchen whose dining room is on the story above or below it. The same-story
# shared-wall search finds nothing there, so adjacent_makeup_air_space falls back to the zones
# stacked over or under the kitchen, read from surface vertices alone: the mid-story surfaces
# stay unmatched and adiabatic. A two-story quick service restaurant is half dining and half
# food preparation, one on each story, and in leg D its kitchen exhausted with no makeup air.
class TestHVACExhaustVerticalMakeup < Minitest::Test
  def setup
    @hvac = OpenstudioStandards::HVAC
    @geometry = OpenstudioStandards::Geometry
    @std = Standard.build('90.1-2013')
  end

  # clockwise floor print, which Space.fromFloorPrint requires
  def print(x0, y0, x1, y1, z)
    polygon = OpenStudio::Point3dVector.new
    [[x0, y0], [x0, y1], [x1, y1], [x1, y0]].each { |x, y| polygon << OpenStudio::Point3d.new(x, y, z) }
    polygon
  end

  def add_space(model, name, story, space_type_name, x0, y0, x1, y1, z)
    space = OpenStudio::Model::Space.fromFloorPrint(print(x0, y0, x1, y1, z), 3.0, model).get
    space.setName(name)
    space.setBuildingStory(story)
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setName(space_type_name)
    space_type.setStandardsSpaceType(space_type_name)
    space.setSpaceType(space_type)
    zone = OpenStudio::Model::ThermalZone.new(model)
    zone.setName("Zone #{name}")
    space.setThermalZone(zone)
    # bar geometry leaves mid-story floors and ceilings adiabatic and unmatched
    space.surfaces.each do |surface|
      next unless surface.surfaceType == 'Floor' || surface.surfaceType == 'RoofCeiling'

      surface.setOutsideBoundaryCondition('Adiabatic')
    end
    zone
  end

  # kitchen on the ground story with an office beside it; dining fills the story above
  def two_story_restaurant(model, dining_overlap: 1.0)
    ground = OpenStudio::Model::BuildingStory.new(model)
    ground.setName('Story ground')
    upper = OpenStudio::Model::BuildingStory.new(model)
    upper.setName('Story 2')
    kitchen = add_space(model, 'Kitchen', ground, 'food preparation', 0.0, 0.0, 10.0, 10.0, 0.0)
    office = add_space(model, 'Office', ground, 'office', 10.0, 0.0, 20.0, 10.0, 0.0)
    shift = 10.0 * (1.0 - dining_overlap)
    dining = add_space(model, 'Dining', upper, 'dining', shift, 0.0, shift + 10.0, 10.0, 3.0)
    [kitchen, office, dining]
  end

  def test_stacked_zones_are_found_with_their_shared_footprint
    model = OpenStudio::Model::Model.new
    kitchen, office, dining = two_story_restaurant(model)

    stacked = @geometry.thermal_zone_get_vertically_adjacent_zones(kitchen)
    assert_equal([dining], stacked.map(&:first), "expected only the dining zone above: #{stacked.map { |z, a| [z.name.to_s, a] }.inspect}")
    assert_in_delta(100.0, stacked.first.last, 0.01, 'the shared footprint is the whole 10 x 10 m plan')

    # the search is symmetric
    assert_equal([kitchen], @geometry.thermal_zone_get_vertically_adjacent_zones(dining).map(&:first))
    # the office shares a wall, not a floor, and is not stacked with anything
    assert_empty(@geometry.thermal_zone_get_vertically_adjacent_zones(office))
    refute_includes(@geometry.thermal_zone_get_adjacent_zones_with_shared_walls(kitchen), dining, 'the wall search must not see the story above')
  end

  def test_partial_overlap_is_measured_and_no_overlap_is_none
    model = OpenStudio::Model::Model.new
    kitchen, _office, dining = two_story_restaurant(model, dining_overlap: 0.3)
    stacked = @geometry.thermal_zone_get_vertically_adjacent_zones(kitchen)
    assert_equal([dining], stacked.map(&:first))
    assert_in_delta(30.0, stacked.first.last, 0.01)

    model = OpenStudio::Model::Model.new
    kitchen, _office, _dining = two_story_restaurant(model, dining_overlap: 0.0)
    assert_empty(@geometry.thermal_zone_get_vertically_adjacent_zones(kitchen), 'a dining room beside, not over, the kitchen is not stacked')
  end

  def test_the_search_leaves_the_surfaces_alone
    model = OpenStudio::Model::Model.new
    kitchen, _office, dining = two_story_restaurant(model)
    before = model.getSurfaces.map { |s| [s.name.to_s, s.outsideBoundaryCondition, s.adjacentSurface.is_initialized, s.vertices.map(&:to_s)] }
    @geometry.thermal_zone_get_vertically_adjacent_zones(kitchen)
    @hvac.adjacent_makeup_air_space(kitchen, @hvac.exhaust_makeup_air_source('food preparation'))
    after = model.getSurfaces.map { |s| [s.name.to_s, s.outsideBoundaryCondition, s.adjacentSurface.is_initialized, s.vertices.map(&:to_s)] }
    assert_equal(before, after, 'surfaces were changed by the adjacency search')
    (kitchen.spaces + dining.spaces).flat_map(&:surfaces).each do |surface|
      next unless surface.surfaceType == 'Floor' || surface.surfaceType == 'RoofCeiling'

      assert_equal('Adiabatic', surface.outsideBoundaryCondition)
      refute(surface.adjacentSurface.is_initialized, "#{surface.name} was matched")
    end
  end

  def test_makeup_air_falls_back_to_the_dining_room_above
    model = OpenStudio::Model::Model.new
    kitchen, _office, dining = two_story_restaurant(model)
    makeup = @hvac.exhaust_makeup_air_source('food preparation')
    refute_nil(makeup)

    space = @hvac.adjacent_makeup_air_space(kitchen, makeup)
    refute_nil(space, 'no makeup space found from the story above')
    assert_equal(dining, space.thermalZone.get)
  end

  def test_a_same_story_dining_room_still_wins
    model = OpenStudio::Model::Model.new
    kitchen, office, dining_above = two_story_restaurant(model)
    # turn the office beside the kitchen into a (smaller) dining room on the same story, and
    # match the ground-story walls so the shared-wall search can see it; the story above is
    # left out of the matching so its floor stays adiabatic
    office.spaces.first.spaceType.get.setStandardsSpaceType('dining')
    office.spaces.first.spaceType.get.setName('dining beside')
    ground_spaces = OpenStudio::Model::SpaceVector.new
    (kitchen.spaces + office.spaces).each { |space| ground_spaces << space }
    OpenStudio::Model.matchSurfaces(ground_spaces)
    assert_includes(@geometry.thermal_zone_get_adjacent_zones_with_shared_walls(kitchen), office)

    space = @hvac.adjacent_makeup_air_space(kitchen, @hvac.exhaust_makeup_air_source('food preparation'))
    assert_equal(office, space.thermalZone.get, 'the shared-wall neighbor should be taken before the stacked one')
    refute_equal(dining_above, space.thermalZone.get)
  end

  def test_create_typical_exhaust_moves_transfer_air_from_the_story_above
    model = OpenStudio::Model::Model.new
    kitchen, _office, dining = two_story_restaurant(model)

    fans = @hvac.create_typical_exhaust(model, @std, makeup_source: 'Adjacent')
    kitchen_fan = fans.find { |f| f.thermalZone.get == kitchen }
    refute_nil(kitchen_fan, 'the kitchen got no exhaust fan')
    assert(kitchen_fan.balancedExhaustFractionSchedule.is_initialized, 'no makeup air: the dining room above was not found')

    mixing = model.getZoneMixings.select { |zm| zm.zoneOrSpace.to_ThermalZone.get == kitchen }
    assert_equal(1, mixing.size, 'expected one zone mixing object into the kitchen')
    assert_equal(dining, mixing.first.sourceZone.get)
    transfer = model.getFanZoneExhausts.select { |f| f.name.to_s.include?('Transfer Air Source') }
    assert_equal(1, transfer.size)
    assert_equal(dining, transfer.first.thermalZone.get)
  end
end
