require_relative '../../helpers/minitest_helper'

class TestSpaceTypeInformation < Minitest::Test
  def setup
    @st = OpenstudioStandards::SpaceType
  end

  # a space type as create_bar builds it from a custom building spec
  def typical_space_type(model, name)
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setName(name)
    space_type.setStandardsSpaceType(name)
    space_type.additionalProperties.setFeature('standards_space_type', name)
    space_type
  end

  # a space type as the prototype path builds it
  def prototype_space_type(model, building_type, name)
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setName("#{building_type} #{name} - 90.1-2013")
    space_type.setStandardsBuildingType(building_type)
    space_type.setStandardsSpaceType(name)
    space_type
  end

  def test_all_level_name_to_level_1
    assert_equal('food preparation', @st.all_level_name_to_level_1('food preparation'))
    assert_equal('food preparation', @st.all_level_name_to_level_1('food preparation - primary school'))
    assert_equal('audience seating', @st.all_level_name_to_level_1('audience seating - gymnasium - primary school'))
    assert_equal('office/enclosed', @st.all_level_name_to_level_1('office/enclosed - > 250 sf'))
    assert_equal('storage', @st.all_level_name_to_level_1('storage - < 50 sf (hospital)'))
    assert_nil(@st.all_level_name_to_level_1('Kitchen'))
    assert_nil(@st.all_level_name_to_level_1(''))
  end

  def test_all_level_name_qualified
    assert_equal('corridor - hospital', @st.all_level_name_qualified('corridor', 'Hospital'))
    assert_equal('corridor - primary school', @st.all_level_name_qualified('corridor', 'PrimarySchool'))
    assert_equal('corridor', @st.all_level_name_qualified('corridor', 'MediumOffice'))
    assert_equal('corridor', @st.all_level_name_qualified('corridor', nil))
  end

  def test_typical_space_types_resolve_to_their_level_1_name
    model = OpenStudio::Model::Model.new
    assert_equal('food preparation', @st.space_type_level_1_name(typical_space_type(model, 'food preparation')))
    assert_equal('food preparation', @st.space_type_level_1_name(typical_space_type(model, 'food preparation - secondary school')))
    assert_equal('corridor', @st.space_type_level_1_name(typical_space_type(model, 'corridor - hospital')))
    assert_equal('dining', @st.space_type_level_1_name(typical_space_type(model, 'dining - cafeteria/fast food')))
    assert_equal('datacenter/low ite', @st.space_type_level_1_name(typical_space_type(model, 'datacenter/low ite')))

    # the additional property wins over a standards space type that differs from it
    mixed = typical_space_type(model, 'patient room')
    mixed.setStandardsSpaceType('PatRoom')
    assert_equal('patient room', @st.space_type_level_1_name(mixed))

    # nothing to go on
    bare = OpenStudio::Model::SpaceType.new(model)
    assert_nil(@st.space_type_level_1_name(bare))
    assert_nil(@st.space_type_level_1_name(typical_space_type(model, 'not a space type')))
  end

  def test_prototype_space_types_translate_through_the_crosswalk
    model = OpenStudio::Model::Model.new
    assert_equal('food preparation', @st.space_type_level_1_name(prototype_space_type(model, 'QuickServiceRestaurant', 'Kitchen')))
    assert_equal('patient room', @st.space_type_level_1_name(prototype_space_type(model, 'Hospital', 'PatRoom')))
    assert_equal('operating room', @st.space_type_level_1_name(prototype_space_type(model, 'Hospital', 'OR')))
    assert_equal('dining', @st.space_type_level_1_name(prototype_space_type(model, 'PrimarySchool', 'Cafeteria')))
    assert_equal('restroom', @st.space_type_level_1_name(prototype_space_type(model, 'Outpatient', 'Toilet')))
    assert_equal('laboratory', @st.space_type_level_1_name(prototype_space_type(model, 'Outpatient', 'Lab')))
    # office building types key on the shared 'Office' row
    assert_equal('office', @st.space_type_level_1_name(prototype_space_type(model, 'MediumOffice', 'OpenOffice')))
    # a prototype name with rows for other building types still resolves
    assert_equal('food preparation', @st.space_type_level_1_name(prototype_space_type(model, 'SmallOffice', 'Kitchen')))
    # DEER prototype names are in the crosswalk too
    assert_equal('food preparation', @st.space_type_level_1_name(prototype_space_type(model, 'Hsp', 'Kitchen')))

    # the crosswalk result is qualified by the building type when the vocabulary has the variant
    assert_equal('corridor - hospital', @st.space_type_all_level_name(prototype_space_type(model, 'Hospital', 'PatCorridor')))
    assert_equal('corridor', @st.space_type_level_1_name(prototype_space_type(model, 'Hospital', 'PatCorridor')))
    assert_equal('food preparation - primary school', @st.space_type_all_level_name(prototype_space_type(model, 'PrimarySchool', 'Kitchen')))
    assert_equal('corridor', @st.space_type_all_level_name(prototype_space_type(model, 'MediumOffice', 'Corridor')))
  end

  def test_space_type_matches_level_1_and_qualified_names
    model = OpenStudio::Model::Model.new
    hospital_corridor = typical_space_type(model, 'corridor - hospital')
    office_corridor = typical_space_type(model, 'corridor')
    school_kitchen = typical_space_type(model, 'food preparation - primary school')
    prototype_pat_corridor = prototype_space_type(model, 'Hospital', 'PatCorridor')

    # a level-1 name matches every variant
    assert(@st.space_type_matches?(hospital_corridor, ['corridor']))
    assert(@st.space_type_matches?(office_corridor, ['corridor']))
    assert(@st.space_type_matches?(school_kitchen, ['food preparation']))
    # a qualified name matches only that variant
    assert(@st.space_type_matches?(hospital_corridor, ['corridor - hospital']))
    assert(!@st.space_type_matches?(office_corridor, ['corridor - hospital']))
    assert(@st.space_type_matches?(prototype_pat_corridor, ['corridor - hospital']))
    assert(!@st.space_type_matches?(school_kitchen, ['dining', 'patient room']))
    assert(!@st.space_type_matches?(OpenStudio::Model::SpaceType.new(model), ['corridor']))
  end

  def test_space_zone_and_air_loop_classification
    model = OpenStudio::Model::Model.new
    kitchen_type = typical_space_type(model, 'food preparation - primary school')
    dining_type = typical_space_type(model, 'dining - primary school')
    office_type = typical_space_type(model, 'office')

    polygon = OpenStudio::Point3dVector.new
    polygon << OpenStudio::Point3d.new(0, 0, 0)
    polygon << OpenStudio::Point3d.new(0, 10, 0)
    polygon << OpenStudio::Point3d.new(10, 10, 0)
    polygon << OpenStudio::Point3d.new(10, 0, 0)

    zones = {}
    { 'food preparation A - Story 1' => kitchen_type, 'dining A - Story 1' => dining_type, 'office A - Story 1' => office_type }.each do |name, space_type|
      space = OpenStudio::Model::Space.fromFloorPrint(polygon, 3.0, model).get
      space.setName(name)
      space.setSpaceType(space_type)
      zone = OpenStudio::Model::ThermalZone.new(model)
      zone.setName("Zone #{name}")
      space.setThermalZone(zone)
      zones[name] = zone
      assert_equal(@st.space_type_level_1_name(space_type), @st.space_level_1_name(space))
    end

    kitchen_zone = zones['food preparation A - Story 1']
    assert_equal(['food preparation'], @st.thermal_zone_level_1_names(kitchen_zone))
    assert(@st.thermal_zone_serves_space_types?(kitchen_zone, ['food preparation', 'dining']))
    assert(!@st.thermal_zone_serves_space_types?(zones['office A - Story 1'], ['food preparation', 'dining']))

    # a kitchen PSZ loop and a loop serving the office and dining
    kitchen_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    kitchen_loop.setName("#{kitchen_zone.name} PSZ-AC")
    kitchen_loop.addBranchForZone(kitchen_zone)
    shared_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    shared_loop.setName('2 Zone PVAV')
    shared_loop.addBranchForZone(zones['office A - Story 1'])
    shared_loop.addBranchForZone(zones['dining A - Story 1'])

    assert(@st.air_loop_hvac_serves_space_types?(kitchen_loop, ['food preparation']))
    assert(!@st.air_loop_hvac_serves_space_types?(shared_loop, ['food preparation']))
    assert(@st.air_loop_hvac_serves_space_types?(shared_loop, ['dining']))
    assert(!@st.air_loop_hvac_serves_space_types?(shared_loop, ['patient room']))
  end
end
