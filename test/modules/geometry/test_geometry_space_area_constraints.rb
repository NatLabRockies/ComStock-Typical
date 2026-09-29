require_relative '../../helpers/minitest_helper'

# Minimum space areas for bar geometry built from space type ratios. A 5,500 ft2 three-story
# hotel in the 2026-09 Kestrel run asked for a 38 ft2 laundry, a 46 ft2 storage room, a 50 ft2
# kitchen and a 70 ft2 retail space; each is narrower than the 3 ft minimum slice, the story
# fill shuffled area between slices to place them, and the per-space-type area check failed by
# hundreds of square feet. With the constraint on, those types are dropped and the rest fit.
class TestGeometrySpaceAreaConstraints < Minitest::Test
  def setup
    @geo = OpenstudioStandards::Geometry
  end

  # ComStock's LargeHotel ratios for every template, with the electrical/mechanical share that
  # generates no geometry folded out, at 5,500 ft2 and three stories.
  HOTEL_ENTRIES = [
    { space_type: 'guest room', ratio: 0.4099, default: true },
    { space_type: 'electrical/mechanical', ratio: 0.1889, space_type_gen: false },
    { space_type: 'corridor', ratio: 0.1736, circ: true },
    { space_type: 'lobby', ratio: 0.1153 },
    { space_type: 'dining', ratio: 0.0751 },
    { space_type: 'retail', ratio: 0.0128 },
    { space_type: 'food preparation', ratio: 0.0091 },
    { space_type: 'storage', ratio: 0.0084 },
    { space_type: 'laundry/washing', ratio: 0.0069 }
  ].freeze

  def hotel_args(total_area_ft2, enforce:)
    { space_type_ratios: HOTEL_ENTRIES.map(&:dup),
      primary_building_type: 'LargeHotel',
      template: 'DOE Ref 1980-2004',
      total_bldg_floor_area: total_area_ft2,
      num_stories_above_grade: 3,
      ns_to_ew_ratio: 1.0,
      wwr: 0.18,
      enforce_space_area_constraints: enforce }
  end

  def hash_for(entries, frac = 1.0)
    { nil => { frac_bldg_area: frac, space_types: entries.map { |name, props| [name, props.dup] }.to_h } }
  end

  def areas(building_type_hash, total)
    building_type_hash.flat_map do |_bt, h|
      gen = h[:space_types].reject { |_n, st| st[:space_type_gen] == false }
      sum = gen.values.sum { |st| st[:ratio] }
      gen.map { |name, st| [name, st[:ratio] / sum * h[:frac_bldg_area] * total] }
    end.to_h
  end

  # --- resolver -------------------------------------------------------------------------

  def test_constraints_resolve_by_keyword_then_default
    assert_equal(10, @geo.space_type_area_constraints('storage')[:drop_priority])
    assert_in_delta(40.0, @geo.space_type_area_constraints('Storage')[:min_area], 1e-9)
    assert(@geo.space_type_area_constraints('classroom/lecture/training')[:essential])
    assert(@geo.space_type_area_constraints('guest room')[:essential])
    # both vocabularies: a standards name and a level-1 typical name
    assert_in_delta(150.0, @geo.space_type_area_constraints('Conference')[:min_area], 1e-9)
    assert_in_delta(150.0, @geo.space_type_area_constraints('conference/meeting/multipurpose')[:min_area], 1e-9)
    # nothing matches: the default row
    default = @geo.space_type_area_constraints('datacenter/low ite')
    assert_in_delta(100.0, default[:min_area], 1e-9)
    assert_equal(50, default[:drop_priority])
    refute(default[:essential])
  end

  def test_per_entry_overrides_win
    c = @geo.space_type_area_constraints('storage', min_area: 500.0, drop_priority: 99, essential: true)
    assert_in_delta(500.0, c[:min_area], 1e-9)
    assert_equal(99, c[:drop_priority])
    assert(c[:essential])
    # an explicit zero disables the minimum
    assert_in_delta(0.0, @geo.space_type_area_constraints('storage', min_area: 0)[:min_area], 1e-9)
  end

  # --- the area pass ----------------------------------------------------------------------

  def test_small_building_drops_the_types_under_their_minimum_least_important_first
    total = 5500.0
    h = hash_for({ 'guest room' => { ratio: 0.5054 }, 'corridor' => { ratio: 0.2140 }, 'lobby' => { ratio: 0.1422 },
                   'dining' => { ratio: 0.0926 }, 'retail' => { ratio: 0.0158 }, 'food preparation' => { ratio: 0.0112 },
                   'storage' => { ratio: 0.0104 }, 'laundry/washing' => { ratio: 0.0085 } })
    report = @geo.apply_space_area_constraints(h, total)

    # food preparation at 62 ft2 is under its 150 ft2 minimum and goes; storage (57 ft2) and
    # laundry (47 ft2) clear their 40 ft2 minimum and stay; retail at 87 ft2 is essential and is
    # raised to its 300 ft2 minimum instead of being dropped
    dropped = report[:dropped].map { |_bt, name, _area, _reason| name }
    assert_equal(['food preparation'], dropped)
    assert_equal(['retail'], report[:bumped].map { |_bt, name, _from, _to| name })
    assert_equal(['guest room', 'corridor', 'lobby', 'dining', 'retail', 'storage', 'laundry/washing'].sort, h[nil][:space_types].keys.sort)
    assert_in_delta(300.0, areas(h, total)['retail'], 1e-6)

    # every survivor sits at or above its minimum and the building still totals 5,500 ft2
    areas(h, total).each { |name, area| assert_operator(area, :>=, @geo.space_type_area_constraints(name)[:min_area] - 1e-6, name) }
    assert_in_delta(1.0, h[nil][:frac_bldg_area], 1e-9)
    assert_in_delta(total, areas(h, total).values.sum, 1e-6)
  end

  def test_survivors_keep_their_proportions
    total = 5500.0
    h = hash_for({ 'guest room' => { ratio: 0.6 }, 'lobby' => { ratio: 0.3 }, 'storage' => { ratio: 0.005 }, 'dining' => { ratio: 0.095 } })
    @geo.apply_space_area_constraints(h, total)
    a = areas(h, total)
    assert_in_delta(2.0, a['guest room'] / a['lobby'], 1e-6, 'the dropped area is shared in proportion')
  end

  def test_large_building_is_untouched
    total = 200_000.0
    h = hash_for({ 'guest room' => { ratio: 0.5054 }, 'corridor' => { ratio: 0.2140 }, 'lobby' => { ratio: 0.1422 },
                   'dining' => { ratio: 0.0926 }, 'retail' => { ratio: 0.0158 }, 'food preparation' => { ratio: 0.0112 },
                   'storage' => { ratio: 0.0104 }, 'laundry/washing' => { ratio: 0.0085 } })
    before = areas(h, total)
    report = @geo.apply_space_area_constraints(h, total)
    assert_empty(report[:dropped])
    assert_empty(report[:bumped])
    areas(h, total).each { |name, area| assert_in_delta(before[name], area, 1e-6, name) }
  end

  def test_a_type_at_exactly_its_minimum_is_kept
    total = 1000.0
    h = hash_for({ 'office' => { ratio: 0.9 }, 'storage' => { ratio: 0.04 } }) # storage = 40 ft2 = its minimum
    report = @geo.apply_space_area_constraints(h, total)
    assert_empty(report[:dropped])
  end

  def test_essential_types_are_raised_from_the_others_surplus
    total = 2000.0
    # classroom essential at 400 ft2 minimum, given 300; office and corridor have surplus
    h = hash_for({ 'office' => { ratio: 0.5 }, 'corridor' => { ratio: 0.35 }, 'classroom/lecture/training' => { ratio: 0.15 } })
    report = @geo.apply_space_area_constraints(h, total)
    assert_empty(report[:dropped])
    assert_equal(['classroom/lecture/training'], report[:bumped].map { |_bt, name, _f, _t| name })
    a = areas(h, total)
    assert_in_delta(400.0, a['classroom/lecture/training'], 1e-6)
    assert_in_delta(total, a.values.sum, 1e-6)
    assert_operator(a['office'], :>=, 100.0 - 1e-6)
    assert_operator(a['corridor'], :>=, 40.0 - 1e-6)
  end

  def test_the_last_type_is_never_dropped
    h = hash_for({ 'storage' => { ratio: 1.0 } })
    report = @geo.apply_space_area_constraints(h, 10.0) # far below the 40 ft2 minimum
    assert_empty(report[:dropped])
    assert_equal(['storage'], h[nil][:space_types].keys)
  end

  def test_non_generating_entries_are_ignored_but_kept
    total = 5500.0
    h = hash_for({ 'guest room' => { ratio: 0.5 }, 'electrical/mechanical' => { ratio: 0.2, space_type_gen: false }, 'storage' => { ratio: 0.005 }, 'lobby' => { ratio: 0.295 } })
    @geo.apply_space_area_constraints(h, total)
    assert(h[nil][:space_types].key?('electrical/mechanical'), 'a non-generating entry is not the pass\'s business')
    refute(h[nil][:space_types].key?('storage'))
  end

  def test_building_types_left_empty_are_removed
    h = { 'LargeHotel' => { frac_bldg_area: 0.98, space_types: { 'GuestRoom' => { ratio: 1.0 } } },
          'RetailStandalone' => { frac_bldg_area: 0.02, space_types: { 'Retail' => { ratio: 1.0, essential: false } } } }
    @geo.apply_space_area_constraints(h, 5000.0) # 100 ft2 retail, below its 300 ft2 minimum
    assert_equal(['LargeHotel'], h.keys)
    assert_in_delta(1.0, h['LargeHotel'][:frac_bldg_area], 1e-9)
  end

  def test_a_building_too_small_for_its_essentials_drops_least_important_first_with_a_warning
    # two essentials that cannot both reach their minimum in 500 ft2
    h = hash_for({ 'classroom/lecture/training' => { ratio: 0.5 }, 'retail' => { ratio: 0.5 } })
    report = @geo.apply_space_area_constraints(h, 500.0)
    assert_equal(1, report[:dropped].size)
    assert_equal('retail', report[:dropped].first[1], 'retail (priority 85) goes before classroom (priority 90)')
    assert_match(/too small/, report[:dropped].first[3])
  end

  # --- through the bar generator ------------------------------------------------------------

  def test_small_hotel_builds_with_the_constraint_and_keeps_the_survivors
    model = OpenStudio::Model::Model.new
    assert(@geo.create_bar_from_space_type_ratios(model, hotel_args(5500.0, enforce: true)), 'the 5,500 ft2 hotel should build with the constraint on')
    names = model.getSpaceTypes.map { |st| st.standardsSpaceType.get }
    refute_includes(names, 'food preparation', 'the 62 ft2 kitchen should have been dropped')
    ['guest room', 'corridor', 'lobby', 'dining', 'retail', 'storage', 'laundry/washing'].each { |kept| assert_includes(names, kept) }
    retail = model.getSpaceTypes.find { |st| st.standardsSpaceType.get == 'retail' }
    assert_in_delta(300.0, OpenStudio.convert(retail.floorArea, 'm^2', 'ft^2').get, 1.0, 'essential retail is raised to its minimum')
    total = OpenStudio.convert(model.getBuilding.floorArea, 'm^2', 'ft^2').get
    assert_in_delta(5500.0, total, 1.0)
  end

  def test_a_large_hotel_is_unchanged_by_the_flag
    with_flag = OpenStudio::Model::Model.new
    assert(@geo.create_bar_from_space_type_ratios(with_flag, hotel_args(200_000.0, enforce: true)))
    without = OpenStudio::Model::Model.new
    assert(@geo.create_bar_from_space_type_ratios(without, hotel_args(200_000.0, enforce: false)))
    by_name = ->(m) { m.getSpaceTypes.map { |st| [st.standardsSpaceType.get, st.floorArea.round(3)] }.sort }
    assert_equal(by_name.call(without), by_name.call(with_flag))
  end

  def test_invalid_entry_overrides_are_rejected
    args = hotel_args(5500.0, enforce: true)
    args[:space_type_ratios][3][:min_area] = -5.0
    refute(@geo.create_bar_from_space_type_ratios(OpenStudio::Model::Model.new, args))
    args = hotel_args(5500.0, enforce: true)
    args[:space_type_ratios][3][:drop_priority] = 'first'
    refute(@geo.create_bar_from_space_type_ratios(OpenStudio::Model::Model.new, args))
  end
end
