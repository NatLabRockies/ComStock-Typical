require_relative '../../helpers/minitest_helper'

# A dedicated point-of-use heater is sized to the draws it serves, not given the 50 gal, 20 kBtu/hr
# of a shared tank, and its standby loss follows its tank size and the number of tanks the water
# heater object stands for. A per-space record can also be put on the shared loop by an override.
class TestSwhPointOfUseSizing < Minitest::Test
  def setup
    @swh = OpenstudioStandards::ServiceWaterHeating
  end

  def polygon
    p = OpenStudio::Point3dVector.new
    p << OpenStudio::Point3d.new(0, 0, 0)
    p << OpenStudio::Point3d.new(0, 10, 0)
    p << OpenStudio::Point3d.new(10, 10, 0)
    p << OpenStudio::Point3d.new(10, 0, 0)
    p
  end

  # spaces of one typical space type, each in its own zone with the given multiplier
  def spaces_of(model, standards_space_type, multipliers)
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setName(standards_space_type)
    space_type.setStandardsSpaceType(standards_space_type)
    multipliers.each_with_index.map do |mult, i|
      space = OpenStudio::Model::Space.fromFloorPrint(polygon, 3.0, model).get
      space.setName("#{standards_space_type} #{i}")
      space.setSpaceType(space_type)
      zone = OpenStudio::Model::ThermalZone.new(model)
      zone.setMultiplier(mult)
      space.setThermalZone(zone)
      space
    end
  end

  def heater_of(loop)
    loop.supplyComponents.find { |c| c.to_WaterHeaterMixed.is_initialized }.to_WaterHeaterMixed.get
  end

  def kbtuh(heater)
    OpenStudio.convert(heater.heaterMaximumCapacity.get, 'W', 'kBtu/hr').get
  end

  def gal(heater)
    OpenStudio.convert(heater.tankVolume.get, 'm^3', 'gal').get
  end

  def test_a_retail_tenant_gets_a_small_point_of_use_heater
    model = OpenStudio::Model::Model.new
    spaces_of(model, 'retail', [1])
    loops = @swh.create_typical_service_water_heating(model)
    assert_equal(1, loops.size)
    heater = heater_of(loops.first)
    # the 1.8 gph tenant draw sizes to about 1.5 kBtu/hr and 1.5 gal, so the floors apply
    assert_in_epsilon(OpenStudio.convert(1500.0, 'W', 'kBtu/hr').get, kbtuh(heater), 0.01)
    assert_in_epsilon(6.0, gal(heater), 0.01)
    # a 6 gal tank loses in proportion to its surface: 1.053 W/K at 40 gal scaled by (6/40)^(2/3)
    assert_in_epsilon(1.053 * (6.0 / 40.0)**(2.0 / 3.0), heater.offCycleLossCoefficienttoAmbientTemperature.get, 0.01)
    assert_in_epsilon(heater.offCycleLossCoefficienttoAmbientTemperature.get, heater.onCycleLossCoefficienttoAmbientTemperature.get, 1e-9)
  end

  def test_a_larger_point_of_use_draw_sizes_above_the_floor
    model = OpenStudio::Model::Model.new
    # the small hotel guest laundry: 0.064 gph/ft2 on 1076 ft2 is about 69 gph
    spaces_of(model, 'laundry/washing - coin-operated laundries', [1])
    loops = @swh.create_typical_service_water_heating(model)
    heater = heater_of(loops.first)
    assert_operator(kbtuh(heater), :>, 20.0, 'a real laundry draw sizes well above the floor')
    assert_operator(gal(heater), :>, 20.0)
    assert_in_epsilon(gal(heater), kbtuh(heater), 0.05, '1 gal of storage per kBtu/hr, as the shared sizing')
  end

  def test_copies_of_a_space_share_one_object_that_loses_as_all_of_them
    model = OpenStudio::Model::Model.new
    spaces_of(model, 'retail', [4])
    heater = heater_of(@swh.create_typical_service_water_heating(model).first)
    assert_equal(4, heater.additionalProperties.getFeatureAsInteger('component_quantity').get)
    assert_in_epsilon(4 * OpenStudio.convert(1500.0, 'W', 'kBtu/hr').get, kbtuh(heater), 0.01)
    assert_in_epsilon(4 * 6.0, gal(heater), 0.01)
    assert_in_epsilon(4 * 1.053 * (6.0 / 40.0)**(2.0 / 3.0), heater.offCycleLossCoefficienttoAmbientTemperature.get, 0.01)
  end

  def test_dwelling_units_keep_their_residential_tank
    model = OpenStudio::Model::Model.new
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setStandardsBuildingType('MidriseApartment')
    space_type.setStandardsSpaceType('Apartment')
    space = OpenStudio::Model::Space.fromFloorPrint(polygon, 3.0, model).get
    space.setSpaceType(space_type)
    space.setThermalZone(OpenStudio::Model::ThermalZone.new(model))
    space.additionalProperties.setFeature('num_units', 3)
    heater = heater_of(@swh.create_typical_service_water_heating(model).first)
    assert_in_epsilon(3 * 20.0, kbtuh(heater), 0.01)
    assert_in_epsilon(3 * 50.0, gal(heater), 0.01)
    assert_in_epsilon(3 * 1.053 * (50.0 / 40.0)**(2.0 / 3.0), heater.offCycleLossCoefficienttoAmbientTemperature.get, 0.01)
  end

  def test_loop_type_override_puts_a_per_space_record_on_the_shared_loop
    model = OpenStudio::Model::Model.new
    retail = spaces_of(model, 'retail', [1, 1])
    overrides = [{ space_type: 'retail', equipment: { '*': { peak_flow_rate_gph_per_floor_area_ft2: 0.00088, mixed_water_temperature_f: 140.0, loop_type: 'Shared' } } }]
    loops = @swh.create_typical_service_water_heating(model, service_water_heating_overrides: overrides)
    assert_equal(1, loops.size, 'both retail spaces draw from one shared loop')
    assert_match(/Shared Service Water Loop/, loops.first.name.to_s)
    area_ft2 = OpenStudio.convert(retail.first.floorArea, 'm^2', 'ft^2').get
    gph = OpenStudio.convert(retail.first.waterUseEquipment.first.waterUseEquipmentDefinition.peakFlowRate, 'm^3/s', 'gal/hr').get
    assert_in_epsilon(0.00088 * area_ft2, gph, 0.01, 'the override rate replaces the record\'s absolute 1.8 gph')
  end
end
