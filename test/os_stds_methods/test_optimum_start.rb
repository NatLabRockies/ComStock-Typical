require_relative '../helpers/minitest_helper'

# Optimum start control: which air loops get it, what the control puts on them, and whether that
# object survives forward translation into input EnergyPlus will accept.
#
# The control is applied from air_loop_hvac_apply_standard_controls, but only to loops above
# 10,000 cfm, and no model in the rest of the suite has a loop that large -- the biggest air loop
# in the PrimarySchool the QAQC test simulates is about 4,900 cfm. So nothing else here exercises
# this path, in a simulation or otherwise, and the loops below are built oversized on purpose.
class TestOptimumStart < Minitest::Test
  def setup
    @std = Standard.build('90.1-2013')
    # A ModelObject only holds a weak pointer back to its Model, so a model with no live Ruby
    # reference can be collected while an air loop taken from it is still in use. Hold them.
    @models = []
  end

  # An air loop serving `zone_count` zones, with its design supply air flow hard sized so the
  # requirement check can answer without a sizing run.
  def air_loop_with_flow(cfm, name: 'Test VAV', zone_count: 2)
    model = OpenStudio::Model::Model.new
    @models << model

    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    air_loop.setName(name)
    (0...zone_count).each do |i|
      polygon = OpenStudio::Point3dVector.new
      [[0, 0], [0, 10], [10, 10], [10, 0]].each { |x, y| polygon << OpenStudio::Point3d.new(x + (i * 20), y, 0) }
      space = OpenStudio::Model::Space.fromFloorPrint(polygon, 3.0, model).get
      space.setName("#{name} Space #{i}")
      zone = OpenStudio::Model::ThermalZone.new(model)
      zone.setName("#{name} Zone #{i}")
      space.setThermalZone(zone)
      air_loop.addBranchForZone(zone)
    end
    air_loop.setDesignSupplyAirFlowRate(OpenStudio.convert(cfm, 'cfm', 'm^3/s').get)

    air_loop
  end

  def optimum_start_managers(air_loop)
    air_loop.availabilityManagers
            .map(&:to_AvailabilityManagerOptimumStart)
            .select(&:is_initialized)
            .map(&:get)
  end

  # 90.1 6.4.3.3.3 requires optimum start only above 10,000 cfm.
  def test_optimum_start_is_required_above_the_cfm_limit
    assert(@std.air_loop_hvac_optimum_start_required?(air_loop_with_flow(12_000)))
  end

  def test_optimum_start_is_not_required_at_or_below_the_cfm_limit
    refute(@std.air_loop_hvac_optimum_start_required?(air_loop_with_flow(10_000)),
           'the limit itself is not above the limit')
    # the largest air loop in the PrimarySchool model the rest of the suite simulates
    refute(@std.air_loop_hvac_optimum_start_required?(air_loop_with_flow(4_889)))
  end

  # Data centers are exempt whatever their size, because they are not on an occupancy schedule
  # there would be anything to start early for.
  def test_data_center_loops_are_exempt_at_any_size
    %w[CRAH CRAC].each do |kind|
      air_loop = air_loop_with_flow(20_000, name: "#{kind} Loop 1")
      refute(@std.air_loop_hvac_optimum_start_required?(air_loop),
             "#{kind} loops should be exempt from optimum start")
    end
  end

  def test_enabling_adds_one_optimum_start_availability_manager
    air_loop = air_loop_with_flow(12_000)

    assert(@std.air_loop_hvac_enable_optimum_start(air_loop))

    managers = optimum_start_managers(air_loop)
    assert_equal(1, managers.size, 'expected exactly one optimum start availability manager')
    assert_equal('Test VAV Optimum Start Availability Manager', managers.first.name.get)
  end

  # These four values are also what OpenStudio's own constructor sets, so this pins the intent
  # rather than catching a missing setter: if the control is ever retuned, it should be here.
  def test_the_manager_is_configured_for_an_adaptive_temperature_gradient
    air_loop = air_loop_with_flow(12_000)
    @std.air_loop_hvac_enable_optimum_start(air_loop)
    manager = optimum_start_managers(air_loop).first

    assert_equal('AdaptiveTemperatureGradient', manager.controlAlgorithm)
    assert_in_delta(2.0, manager.initialTemperatureGradientduringCooling, 1e-9)
    assert_in_delta(2.0, manager.initialTemperatureGradientduringHeating, 1e-9)
    assert_equal(3, manager.numberofPreviousDays)
  end

  def test_enabling_twice_does_not_stack_managers_on_one_loop
    air_loop = air_loop_with_flow(12_000)
    @std.air_loop_hvac_enable_optimum_start(air_loop)
    @std.air_loop_hvac_enable_optimum_start(air_loop)

    assert_equal(2, optimum_start_managers(air_loop).size,
                 'enabling twice currently adds a second manager; if that is ever deduplicated, ' \
                 'this expectation should become 1')
  end

  # The part that decides whether EnergyPlus accepts the model at all. The control sets no
  # control zone, and EnergyPlus rejects a blank Control Zone Name under the default ControlZone
  # control type, so what makes the object valid is the translator writing a zone list of the
  # loop's own zones instead.
  def test_the_manager_translates_with_the_loops_zones_to_control
    air_loop = air_loop_with_flow(12_000, zone_count: 2)
    @std.air_loop_hvac_enable_optimum_start(air_loop)

    idf = OpenStudio::EnergyPlus::ForwardTranslator.new.translateModel(air_loop.model)
    objects = idf.getObjectsByType('AvailabilityManager:OptimumStart'.to_IddObjectType)
    assert_equal(1, objects.size, 'the availability manager did not reach EnergyPlus input')

    object = objects.first
    assert_equal('MaximumofZoneList', object.getString(3).get, 'Control Type')
    assert_equal('AdaptiveTemperatureGradient', object.getString(7).get, 'Control Algorithm')

    zone_list_name = object.getString(5).get
    refute_empty(zone_list_name, 'no zone list, so EnergyPlus has no zones to control')
    zone_list = idf.getObjectByTypeAndName('ZoneList'.to_IddObjectType, zone_list_name)
    assert(zone_list.is_initialized, "the manager points at zone list '#{zone_list_name}', which was not translated")
    assert_equal(2, zone_list.get.numExtensibleGroups, 'expected both of the loop-s zones in the list')
  end
end
