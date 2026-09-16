require_relative '../../helpers/minitest_helper'

# Two places in the library pick one object out of a collection of model objects. OpenStudio
# hands those collections back in handle order, and handles are random, so the order is not the
# same twice. An unsorted pick therefore makes the model itself depend on the run, which is not
# visible in any single result and only shows up as two runs of identical inputs disagreeing.
#
# These tests pin the contract that makes the pick stable: the collection is sorted first, and
# OpenStudio sorts model objects by name, so the winner is the name-sorted one. They build the
# same model repeatedly rather than asserting once, because a single build cannot distinguish a
# deterministic pick from a lucky one.
class TestGeometryDeterminism < Minitest::Test
  BUILDS = 25

  # A space with two ground-contact floors of different size. The library warns about this case
  # rather than rejecting it, so whichever floor is picked becomes the area and perimeter of the
  # F-factor foundation construction.
  def space_with_two_ground_floors
    model = OpenStudio::Model::Model.new
    space = OpenStudio::Model::Space.new(model)
    space.setName('two ground floors')
    # Created largest first, and named so that sorting by name reverses that order: if the pick
    # followed creation or handle order rather than the sort it would land on the 100 m2 floor.
    #
    # The two floors sit at different heights, which is the multi-level case the library's own
    # warning anticipates, and it is what lets the perimeter tell them apart. The perimeter
    # helper compares only a floor's z value against each wall edge, never its footprint, so two
    # ground floors sharing a z would give the same perimeter whichever one won and the
    # perimeter test would prove nothing.
    [['zzz large floor', 10.0, 0.0], ['aaa small floor', 4.0, 3.0]].each do |name, side, z|
      points = OpenStudio::Point3dVector.new
      points << OpenStudio::Point3d.new(0.0, 0.0, z)
      points << OpenStudio::Point3d.new(side, 0.0, z)
      points << OpenStudio::Point3d.new(side, side, z)
      points << OpenStudio::Point3d.new(0.0, side, z)
      surface = OpenStudio::Model::Surface.new(points, model)
      surface.setName(name)
      surface.setSpace(space)
      surface.setSurfaceType('Floor')
      surface.setOutsideBoundaryCondition('Ground')
    end
    # Two outdoor walls rising 1.5 m from the large floor. Their edges are at z 0.0 and 1.5, so
    # they register against the large floor at z 0.0 and not against the small floor at z 3.0:
    # the perimeter is 20 m if the large floor is picked and 0 m if the small one is.
    [['west wall', [0.0, 0.0], [0.0, 10.0]], ['south wall', [0.0, 0.0], [10.0, 0.0]]].each do |name, a, b|
      points = OpenStudio::Point3dVector.new
      points << OpenStudio::Point3d.new(a[0], a[1], 0.0)
      points << OpenStudio::Point3d.new(b[0], b[1], 0.0)
      points << OpenStudio::Point3d.new(b[0], b[1], 1.5)
      points << OpenStudio::Point3d.new(a[0], a[1], 1.5)
      surface = OpenStudio::Model::Surface.new(points, model)
      surface.setName(name)
      surface.setSpace(space)
      surface.setSurfaceType('Wall')
      surface.setOutsideBoundaryCondition('Outdoors')
    end
    space
  end

  # The premise these tests rest on: the collection order really does vary between builds. If
  # this ever stops being true the tests below still pass but stop proving anything, so assert
  # it rather than assume it.
  def test_surface_order_varies_between_builds
    orders = Array.new(BUILDS) { space_with_two_ground_floors.surfaces.map { |s| s.name.to_s } }
    assert_operator orders.uniq.size, :>, 1,
                    'surface order no longer varies between builds, so the determinism tests ' \
                    'below no longer prove anything; check whether OpenStudio changed how it ' \
                    'orders a space\'s surfaces before deleting them'
  end

  def test_f_floor_area_picks_the_same_floor_every_build
    areas = Array.new(BUILDS) { OpenstudioStandards::Geometry.space_get_f_floor_area(space_with_two_ground_floors).round(6) }
    assert_equal 1, areas.uniq.size,
                 "space_get_f_floor_area returned #{areas.uniq.inspect} across #{BUILDS} builds " \
                 'of the same space; the ground floor pick is following handle order again'
    assert_in_delta 16.0, areas.first, 0.001,
                    'expected the name-sorted first ground floor (aaa small floor, 16 m2)'
  end

  def test_f_floor_perimeter_picks_the_same_floor_every_build
    perimeters = Array.new(BUILDS) { OpenstudioStandards::Geometry.space_get_f_floor_perimeter(space_with_two_ground_floors).round(6) }
    assert_equal 1, perimeters.uniq.size,
                 "space_get_f_floor_perimeter returned #{perimeters.uniq.inspect} across " \
                 "#{BUILDS} builds of the same space; the ground floor pick is following " \
                 'handle order again'
    assert_in_delta 0.0, perimeters.first, 0.001,
                    'expected the name-sorted first ground floor, the one at z 3.0 that no ' \
                    'wall edge reaches'
  end

  # The other pick of the same kind: the largest space in a zone supplies that zone's design
  # specification outdoor air, and on an exact tie in floor area an unsorted select hands it to
  # whichever space came back first. Two identical spaces make the tie certain.
  def zone_with_two_equal_spaces
    model = OpenStudio::Model::Model.new
    zone = OpenStudio::Model::ThermalZone.new(model)
    zone.setName('tied zone')
    %w[zzz_space aaa_space].each do |name|
      space = OpenStudio::Model::Space.new(model)
      space.setName(name)
      space.setThermalZone(zone)
      points = OpenStudio::Point3dVector.new
      points << OpenStudio::Point3d.new(0.0, 0.0, 0.0)
      points << OpenStudio::Point3d.new(5.0, 0.0, 0.0)
      points << OpenStudio::Point3d.new(5.0, 5.0, 0.0)
      points << OpenStudio::Point3d.new(0.0, 5.0, 0.0)
      surface = OpenStudio::Model::Surface.new(points, model)
      surface.setName("#{name} floor")
      surface.setSpace(space)
      surface.setSurfaceType('Floor')
      surface.setOutsideBoundaryCondition('Ground')
      # each space gets its own outdoor air object, named after it, so the one the zone ends up
      # with names the space that won the tie
      oa = OpenStudio::Model::DesignSpecificationOutdoorAir.new(model)
      oa.setName("#{name} oa")
      oa.setOutdoorAirMethod('Sum')
      oa.setOutdoorAirFlowperPerson(0.0)
      oa.setOutdoorAirFlowperFloorArea(0.001)
      space.setDesignSpecificationOutdoorAir(oa)
    end
    zone
  end

  def test_largest_space_tie_resolves_the_same_way_every_build
    std = Standard.build('90.1-2013')
    # Drive the library's own selection rather than restating it here: model_add_ideal_air_loads
    # gives the zone the design specification outdoor air of its largest space, and the two
    # spaces are tied, so the object it lands on is the pick under test.
    winners = Array.new(BUILDS) do
      zone = zone_with_two_equal_spaces
      std.model_add_ideal_air_loads(zone.model, [zone], include_outdoor_air: true)
      ideal = zone.model.getZoneHVACIdealLoadsAirSystems.first
      oa = ideal.designSpecificationOutdoorAirObject
      oa.is_initialized ? oa.get.name.to_s : 'none'
    end
    assert_equal 1, winners.uniq.size,
                 "the largest-space tie resolved to #{winners.uniq.inspect} across #{BUILDS} " \
                 'builds; sort the zone\'s spaces before selecting the largest'
    refute_equal 'none', winners.first,
                 'the fixture gave neither space a design specification outdoor air object, so ' \
                 'this test cannot see which space was picked'
    assert_equal 'aaa_space oa', winners.first, 'expected the name-sorted first of the tied spaces'
  end
end
