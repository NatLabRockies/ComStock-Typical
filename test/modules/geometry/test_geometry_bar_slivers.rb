require_relative '../../helpers/minitest_helper'

# Sliver spaces from the bar generator, from three buildings in the 2026-09 100k ComStock run.
#
# The outpatient and the school are drawn as two bars. Splitting each space type's area
# between the bars handed the secondary bar 0.14 m2 of recovery rooms (three 1 cm slices)
# and the primary bar 0.2 m2 of dining (a 2.3 cm slice); EnergyPlus's heat balance diverged
# in them. The school's story fill then moved that 0.2 m2 dining slice off a story to make
# room for a 1.75 m2 classroom slice, which grew to 1.95 m2 and stayed a sliver. The
# warehouse is one bar, three stories of 667 ft2 holding 1,394 and 606 ft2 of storage: the
# 606 ft2 type was placed first on every story, the 61 ft2 remainder tripped the sliver test,
# and on the top story the fix moved the 606 ft2 type to a next story that does not exist.
class TestGeometryBarSlivers < Minitest::Test
  MIN_SLICE_M = OpenStudio.convert(3.0, 'ft', 'm').get

  # Outpatient 21000 ft2 x 3 stories, ComStock DEER Pre-1975
  ARGS_61921 = {
    bar_division_method: 'Multiple Space Types - Individual Stories Sliced',
    bar_sep_dist_mult: 10.0,
    bar_width: 0.0,
    bottom_story_ground_exposed_floor: true,
    building_rotation: 315.0,
    custom_height_bar: true,
    double_loaded_corridor: 'Primary Space Type',
    floor_height: 0.0,
    make_mid_story_surfaces_adiabatic: true,
    ns_to_ew_ratio: 1.0,
    num_stories_above_grade: 3,
    num_stories_below_grade: 0,
    party_wall_fraction: 0.0,
    party_wall_stories_east: 0,
    party_wall_stories_north: 0,
    party_wall_stories_south: 0,
    party_wall_stories_west: 0,
    perim_mult: 0.0,
    single_floor_area: 0.0,
    space_type_sort_logic: 'Building Type > Size',
    top_story_exterior_exposed_roof: true,
    total_bldg_floor_area: 21000.0,
    wwr: 0.63,
    building_form_defaults: { aspect_ratio: 1.6, wwr: 0.2, typical_story: 10.0, perim_mult: 1.121 },
    template: 'ComStock DEER Pre-1975', primary_building_type: 'Outpatient',
    space_type_ratios: [
      { space_type: 'exam/treatment', ratio: 0.1249, default: false, space_type_gen: true },
      { space_type: 'storage', ratio: 0.1521, default: false, space_type_gen: true },
      { space_type: 'dining', ratio: 0.0103, default: false, space_type_gen: true },
      { space_type: 'conference/meeting/multipurpose', ratio: 0.0082, default: false, space_type_gen: true },
      { space_type: 'electrical/mechanical', ratio: 0.0131, default: false, space_type_gen: true },
      { space_type: 'corridor', ratio: 0.1924, default: false, circ: true, space_type_gen: true },
      { space_type: 'datacenter/low ite', ratio: 0.0027, default: false, space_type_gen: true },
      { space_type: 'lobby', ratio: 0.0517, default: false, space_type_gen: true },
      { space_type: 'locker room', ratio: 0.019, default: false, space_type_gen: true },
      { space_type: 'lounge/breakroom', ratio: 0.0293, default: false, space_type_gen: true },
      { space_type: 'imaging', ratio: 0.0368, default: false, space_type_gen: true },
      { space_type: 'nurses station', ratio: 0.0189, default: false, space_type_gen: true },
      { space_type: 'office', ratio: 0.1828, default: false, space_type_gen: true },
      { space_type: 'operating room', ratio: 0.0545, default: false, space_type_gen: true },
      { space_type: 'recovery', ratio: 0.0232, default: false, space_type_gen: true },
      { space_type: 'physical therapy', ratio: 0.0462, default: false, space_type_gen: true },
      { space_type: 'stairwell', ratio: 0.0146, default: false, space_type_gen: true },
      { space_type: 'restroom', ratio: 0.0193, default: false, space_type_gen: true }
    ]
  }.freeze

  # SecondarySchool 5500 ft2 x 4 stories, ComStock DOE Ref Pre-1980
  ARGS_40396 = {
    bar_division_method: 'Multiple Space Types - Individual Stories Sliced',
    bar_sep_dist_mult: 10.0,
    bar_width: 0.0,
    bottom_story_ground_exposed_floor: true,
    building_rotation: 180.0,
    custom_height_bar: true,
    double_loaded_corridor: 'Primary Space Type',
    floor_height: 0.0,
    make_mid_story_surfaces_adiabatic: true,
    ns_to_ew_ratio: 2.0,
    num_stories_above_grade: 4,
    num_stories_below_grade: 0,
    party_wall_fraction: 0.0,
    party_wall_stories_east: 0,
    party_wall_stories_north: 0,
    party_wall_stories_south: 0,
    party_wall_stories_west: 0,
    perim_mult: 0.0,
    single_floor_area: 0.0,
    space_type_sort_logic: 'Building Type > Size',
    top_story_exterior_exposed_roof: true,
    total_bldg_floor_area: 5500.0,
    wwr: 0.18,
    building_form_defaults: { aspect_ratio: 2.1, wwr: 0.33, typical_story: 13.0, perim_mult: 1.568 },
    template: 'ComStock DOE Ref Pre-1980', primary_building_type: 'SecondarySchool',
    space_type_ratios: [
      { space_type: 'audience seating - secondary school', ratio: 0.0504, story_height: 26.0, default: false, space_type_gen: true },
      { space_type: 'dining - secondary school', ratio: 0.0319, default: false, space_type_gen: true },
      { space_type: 'classroom/lecture/training', ratio: 0.3528, default: true, space_type_gen: true },
      { space_type: 'corridor - secondary school', ratio: 0.2144, default: false, circ: true, space_type_gen: true },
      { space_type: 'playing area - secondary school', ratio: 0.1009, story_height: 26.0, default: false, space_type_gen: true },
      { space_type: 'audience seating - gymnasium - secondary school', ratio: 0.0637, story_height: 26.0, default: false, space_type_gen: true },
      { space_type: 'food preparation - secondary school', ratio: 0.011, default: false, space_type_gen: true },
      { space_type: 'library - secondary school', ratio: 0.0429, default: false, space_type_gen: true },
      { space_type: 'lobby - secondary school', ratio: 0.0214, default: false, space_type_gen: true },
      { space_type: 'electrical/mechanical', ratio: 0.0349, default: false, space_type_gen: true },
      { space_type: 'office', ratio: 0.0543, default: false, space_type_gen: true },
      { space_type: 'restroom - secondary school', ratio: 0.0214, default: false, space_type_gen: true }
    ]
  }.freeze

  # Warehouse 2000 ft2 x 3 stories, ComStock DOE Ref 1980-2004
  ARGS_49289 = {
    bar_division_method: 'Multiple Space Types - Individual Stories Sliced',
    bar_sep_dist_mult: 10.0,
    bar_width: 0.0,
    bottom_story_ground_exposed_floor: true,
    building_rotation: 0.0,
    custom_height_bar: true,
    double_loaded_corridor: 'Primary Space Type',
    floor_height: 0.0,
    make_mid_story_surfaces_adiabatic: true,
    ns_to_ew_ratio: 1.0,
    num_stories_above_grade: 3,
    num_stories_below_grade: 0,
    party_wall_fraction: 0.0,
    party_wall_stories_east: 0,
    party_wall_stories_north: 0,
    party_wall_stories_south: 0,
    party_wall_stories_west: 0,
    perim_mult: 0.0,
    single_floor_area: 0.0,
    space_type_sort_logic: 'Building Type > Size',
    top_story_exterior_exposed_roof: true,
    total_bldg_floor_area: 2000.0,
    wwr: 0.06,
    building_form_defaults: { aspect_ratio: 2.2, wwr: 0.0, typical_story: 28.0, perim_mult: 1.0 },
    template: 'ComStock DOE Ref 1980-2004', primary_building_type: 'Warehouse',
    space_type_ratios: [
      { space_type: 'storage - warehouse - medium to bulky palletized items', ratio: 0.6628, default: true, space_type_gen: true },
      { space_type: 'storage - warehouse - smaller hand-carried items', ratio: 0.2882, default: false, space_type_gen: true },
      { space_type: 'office', ratio: 0.049, story_height: 14.0, wwr: 0.71, default: false, space_type_gen: true }
    ]
  }.freeze

  # Hospital 21000 ft2 x 5 stories, ComStock DOE Ref Pre-1980. The story fill held back a
  # whole 64 m2 dining slice for the next story but left the type in the story's list with
  # 0.0 m2, which became a zero-width surface and a fatal in the 2026-09 run.
  ARGS_83001 = {
    bar_division_method: 'Multiple Space Types - Individual Stories Sliced',
    bar_sep_dist_mult: 10.0,
    bar_width: 0.0,
    bottom_story_ground_exposed_floor: true,
    building_rotation: 225.0,
    custom_height_bar: true,
    double_loaded_corridor: 'Primary Space Type',
    floor_height: 0.0,
    make_mid_story_surfaces_adiabatic: true,
    ns_to_ew_ratio: 2.0,
    num_stories_above_grade: 5,
    num_stories_below_grade: 0,
    party_wall_fraction: 0.0,
    party_wall_stories_east: 0,
    party_wall_stories_north: 0,
    party_wall_stories_south: 0,
    party_wall_stories_west: 0,
    perim_mult: 0.0,
    single_floor_area: 0.0,
    space_type_sort_logic: 'Building Type > Size',
    top_story_exterior_exposed_roof: true,
    total_bldg_floor_area: 21000.0,
    wwr: 0.06,
    building_form_defaults: { aspect_ratio: 1.33, wwr: 0.16, typical_story: 14.0, perim_mult: 1.0 },
    template: 'ComStock DOE Ref Pre-1980', primary_building_type: 'Hospital',
    space_type_ratios: [
      { space_type: 'electrical/mechanical', ratio: 0.1667, default: false, space_type_gen: false },
      { space_type: 'corridor - hospital', ratio: 0.1741, default: false, circ: true, space_type_gen: true },
      { space_type: 'dining - cafeteria/fast food', ratio: 0.0311, default: false, space_type_gen: true },
      { space_type: 'exam/treatment', ratio: 0.0374, default: false, space_type_gen: true },
      { space_type: 'nurses station', ratio: 0.2572, default: false, space_type_gen: true },
      { space_type: 'emergency room', ratio: 0.0075, default: false, space_type_gen: true },
      { space_type: 'patient room', ratio: 0.096, default: false, space_type_gen: true },
      { space_type: 'food preparation', ratio: 0.0414, default: false, space_type_gen: true },
      { space_type: 'laboratory', ratio: 0.0236, default: false, space_type_gen: true },
      { space_type: 'lobby', ratio: 0.0657, default: false, space_type_gen: true },
      { space_type: 'office', ratio: 0.0286, default: false, space_type_gen: true },
      { space_type: 'operating room', ratio: 0.0273, default: false, space_type_gen: true },
      { space_type: 'physical therapy', ratio: 0.0217, default: false, space_type_gen: true },
      { space_type: 'imaging', ratio: 0.0217, default: false, space_type_gen: true }
    ]
  }.freeze

  # PrimarySchool 2000 ft2 x 2 stories, ComStock DOE Ref Pre-1980: two bars 2 m wide. The
  # story fill held back the last two types on a story of the second bar with nothing after
  # them to fill it, so the restroom was stretched to twice its area.
  ARGS_73508 = {
    bar_division_method: 'Multiple Space Types - Individual Stories Sliced',
    bar_sep_dist_mult: 10.0,
    bar_width: 0.0,
    bottom_story_ground_exposed_floor: true,
    building_rotation: 0.0,
    custom_height_bar: true,
    double_loaded_corridor: 'Primary Space Type',
    floor_height: 0.0,
    make_mid_story_surfaces_adiabatic: true,
    ns_to_ew_ratio: 5.0,
    num_stories_above_grade: 2,
    num_stories_below_grade: 0,
    party_wall_fraction: 0.0,
    party_wall_stories_east: 0,
    party_wall_stories_north: 0,
    party_wall_stories_south: 0,
    party_wall_stories_west: 0,
    perim_mult: 0.0,
    single_floor_area: 0.0,
    space_type_sort_logic: 'Building Type > Size',
    top_story_exterior_exposed_roof: true,
    total_bldg_floor_area: 2000.0,
    wwr: 0.38,
    building_form_defaults: { aspect_ratio: 2.8, wwr: 0.35, typical_story: 13.0, perim_mult: 1.914 },
    template: 'ComStock DOE Ref Pre-1980', primary_building_type: 'PrimarySchool',
    space_type_ratios: [
      { space_type: 'dining - primary school', ratio: 0.0458, default: false, space_type_gen: true },
      { space_type: 'classroom/lecture/training', ratio: 0.561, default: true, space_type_gen: true },
      { space_type: 'corridor - primary school', ratio: 0.1633, default: false, circ: true, space_type_gen: true },
      { space_type: 'playing area - primary school', ratio: 0.052, default: false, space_type_gen: true },
      { space_type: 'food preparation - primary school', ratio: 0.0244, default: false, space_type_gen: true },
      { space_type: 'lobby - primary school', ratio: 0.0249, default: false, space_type_gen: true },
      { space_type: 'electrical/mechanical', ratio: 0.0367, default: false, space_type_gen: true },
      { space_type: 'office', ratio: 0.0642, default: false, space_type_gen: true },
      { space_type: 'restroom - primary school', ratio: 0.0277, default: false, space_type_gen: true }
    ]
  }.freeze

  def build(args)
    model = OpenStudio::Model::Model.new
    copy = Marshal.load(Marshal.dump(args)) # the generator edits its arguments
    copy[:enforce_space_area_constraints] = true
    [OpenstudioStandards::Geometry.create_bar_from_space_type_ratios(model, copy), model]
  end

  # the narrower of a space's two floor extents: a bar slice is a strip across the bar
  def narrowest_extent_m(space)
    points = space.surfaces.select { |s| s.surfaceType == 'Floor' }.flat_map(&:vertices)
    xs = points.map(&:x)
    ys = points.map(&:y)
    [xs.max - xs.min, ys.max - ys.min].min
  end

  def assert_no_slivers(model, label)
    model.getSpaces.sort_by { |s| s.name.to_s }.each do |space|
      assert_operator(space.floorArea, :>=, 1.0, "#{label}: #{space.name} has #{space.floorArea.round(3)} m2")
      assert_operator(narrowest_extent_m(space), :>=, MIN_SLICE_M - 0.02, "#{label}: #{space.name} is #{narrowest_extent_m(space).round(3)} m across")
    end
  end

  def areas_by_type_ft2(model)
    model.getSpaceTypes.map { |st| [st.standardsSpaceType.get, OpenStudio.convert(st.floorArea, 'm^2', 'ft^2').get] }.to_h
  end

  # --- the rebalance on its own ---------------------------------------------------------

  def entry(area)
    { floor_area: area, space_type: 'x' }
  end

  def test_a_secondary_sliver_trades_places_with_a_type_present_in_both_bars
    primary = { 'recovery' => entry(45.3), 'operating room' => entry(33.0), 'office' => entry(300.0) }
    secondary = { 'recovery' => entry(0.14), 'operating room' => entry(73.0), 'restroom' => entry(37.7) }
    moves = OpenstudioStandards::Geometry.rebalance_bar_split_slivers(primary, secondary, 14.3, 11.8)
    assert_equal([['recovery', 0.14, 'secondary', 'primary']], moves)
    refute(secondary.key?('recovery'))
    assert_in_delta(45.44, primary['recovery'][:floor_area], 1e-9)
    assert_in_delta(73.14, secondary['operating room'][:floor_area], 1e-9)
    assert_in_delta(32.86, primary['operating room'][:floor_area], 1e-9)
    # totals per type and per bar are unchanged
    assert_in_delta(45.3 + 33.0 + 300.0, primary.values.sum { |v| v[:floor_area] }, 1e-9)
    assert_in_delta(0.14 + 73.0 + 37.7, secondary.values.sum { |v| v[:floor_area] }, 1e-9)
  end

  def test_a_primary_sliver_moves_to_the_secondary_bar
    primary = { 'dining' => entry(0.2), 'classroom' => entry(170.0) }
    secondary = { 'dining' => entry(20.1), 'classroom' => entry(33.7), 'restroom' => entry(13.6) }
    moves = OpenstudioStandards::Geometry.rebalance_bar_split_slivers(primary, secondary, 3.9, 3.9)
    assert_equal([['dining', 0.2, 'primary', 'secondary']], moves)
    refute(primary.key?('dining'))
    assert_in_delta(20.3, secondary['dining'][:floor_area], 1e-9)
    assert_in_delta(33.5, secondary['classroom'][:floor_area], 1e-9)
    assert_in_delta(170.2, primary['classroom'][:floor_area], 1e-9)
  end

  def test_a_donor_may_give_exactly_all_of_its_share
    primary = { 'a' => entry(0.5), 'b' => entry(100.0) }
    secondary = { 'a' => entry(30.0), 'b' => entry(0.5) }
    OpenstudioStandards::Geometry.rebalance_bar_split_slivers(primary, secondary, 5.0, 5.0)
    assert_equal(['b'], primary.keys)
    assert_equal(['a'], secondary.keys)
    assert_in_delta(30.5, secondary['a'][:floor_area], 1e-9)
    assert_in_delta(100.5, primary['b'][:floor_area], 1e-9)
  end

  def test_a_sliver_with_no_donor_or_no_share_to_grow_is_left_alone
    # 'a' has no share in the primary bar to grow, 'c' has no donor with a primary share
    primary = { 'b' => entry(100.0) }
    secondary = { 'a' => entry(0.5), 'b' => entry(30.0), 'c' => entry(0.4) }
    moves = OpenstudioStandards::Geometry.rebalance_bar_split_slivers(primary, secondary, 5.0, 5.0)
    assert_empty(moves)
    assert_in_delta(0.5, secondary['a'][:floor_area], 1e-9)
    assert_in_delta(0.4, secondary['c'][:floor_area], 1e-9)
  end

  # --- through the generator --------------------------------------------------------------

  def test_two_bar_outpatient_has_no_sliver_spaces
    ok, model = build(ARGS_61921)
    assert(ok, 'the outpatient should build')
    assert_no_slivers(model, 'outpatient 61921')
    assert_in_delta(21000.0 * 0.0232, areas_by_type_ft2(model)['recovery'], 5.0, 'recovery keeps its area')
  end

  def test_two_bar_school_has_no_sliver_spaces
    ok, model = build(ARGS_40396)
    assert(ok, 'the school should build')
    assert_no_slivers(model, 'school 40396')
  end

  def test_hospital_swapped_out_slice_leaves_the_story_and_builds
    ok, model = build(ARGS_83001)
    assert(ok, 'the hospital should build: a slice held back for the next story must not stay as a 0 m2 entry')
    model.getSurfaces.each { |s| assert_operator(s.grossArea, :>, 0.01, "#{s.name} has no area") }
    # the story fill tests slice areas against the whole multiplied story, so an 11 m2 per
    # floor food preparation slice on the x3 mid story passes as 33 m2 and comes out 0.79 m
    # wide; that is a separate blind spot, so only zero-width slices are ruled out here
    model.getSpaces.each { |space| assert_operator(narrowest_extent_m(space), :>=, 0.5, "#{space.name} is #{narrowest_extent_m(space).round(3)} m across") }
  end

  def test_tiny_two_bar_school_keeps_its_areas
    ok, model = build(ARGS_73508)
    assert(ok, 'the school should build: every space type within 1 m2 of target')
    areas = areas_by_type_ft2(model)
    # 65 ft2: its ratio over the five types the area constraint keeps (dining, playing area,
    # food preparation and lobby are under their minimums at 2,000 ft2)
    assert_in_delta(2000.0 * 0.0277 / 0.8529, areas['restroom - primary school'], 2.0, 'the restroom is not stretched to fill a story')
    # the bars are 2 m wide, so the double loaded corridor children are narrow by construction;
    # the slices are still real, not zero-width
    model.getSpaces.each { |space| assert_operator(space.floorArea, :>=, 0.5, "#{space.name} has #{space.floorArea.round(3)} m2") }
  end

  def test_three_story_warehouse_places_both_storage_types
    ok, model = build(ARGS_49289)
    assert(ok, 'the warehouse should build: both storage types within 1 m2 of target')
    areas = areas_by_type_ft2(model)
    assert_in_delta(2000.0 * 0.6628 / (0.6628 + 0.2882), areas['storage - warehouse - medium to bulky palletized items'], 2.0)
    assert_in_delta(2000.0 * 0.2882 / (0.6628 + 0.2882), areas['storage - warehouse - smaller hand-carried items'], 2.0)
    model.getSpaces.each { |space| assert_operator(space.floorArea, :>=, 1.0, "#{space.name} has #{space.floorArea.round(3)} m2") }
  end
end
