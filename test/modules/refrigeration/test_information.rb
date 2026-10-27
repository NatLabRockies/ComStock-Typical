require_relative '../../helpers/minitest_helper'

class TestRefrigerationInformation < Minitest::Test
  def setup
    @geo = OpenstudioStandards::Geometry
    @refrig = OpenstudioStandards::Refrigeration
  end

  def test_refrigeration_case_zone
    model = OpenStudio::Model::Model.new
    args = {}
    args['total_bldg_floor_area'] = 50000.0
    args['bldg_type_a'] = 'SuperMarket'
    result = @geo.create_bar_from_building_type_ratios(model, args)

    # get case zone
    zone = @refrig.refrigeration_case_zone(model)
    assert_equal('Zone SuperMarket Sales B  - Story ground', zone.name.to_s)
  end

  def test_refrigeration_walkin_zone
    model = OpenStudio::Model::Model.new
    args = {}
    args['total_bldg_floor_area'] = 50000.0
    args['bldg_type_a'] = 'SuperMarket'
    result = @geo.create_bar_from_building_type_ratios(model, args)

    # get case zone
    zone = @refrig.refrigeration_walkin_zone(model)
    assert_equal('Zone SuperMarket DryStorage B  - Story ground', zone.name.to_s)
  end

  def test_refrigeration_case_zone_multistory
    model = OpenStudio::Model::Model.new
    args = {}
    args['total_bldg_floor_area'] = 50000.0
    args['bldg_type_a'] = 'SuperMarket'
    args['num_stories_above_grade'] = 4
    result = @geo.create_bar_from_building_type_ratios(model, args)

    # sales zones are only on the mid (multiplier 2) and top stories, so the top story is chosen over the larger mid story zone
    zone = @refrig.refrigeration_case_zone(model)
    assert_equal('Zone SuperMarket Sales B  - Story top', zone.name.to_s)
    assert_equal(1, zone.multiplier)

    # dry storage zones are on the ground and mid stories
    zone = @refrig.refrigeration_walkin_zone(model)
    assert_equal('Zone SuperMarket DryStorage B  - Story ground', zone.name.to_s)
  end

  def test_refrigeration_preferred_zone
    model = OpenStudio::Model::Model.new
    args = {}
    args['total_bldg_floor_area'] = 50000.0
    args['bldg_type_a'] = 'SuperMarket'
    args['num_stories_above_grade'] = 4
    result = @geo.create_bar_from_building_type_ratios(model, args)
    zones = model.getThermalZones.to_a

    # the choice does not depend on zone order
    picks = 10.times.map { |i| @refrig.refrigeration_preferred_zone(zones.shuffle(random: Random.new(i))).name.to_s }
    picks << @refrig.refrigeration_preferred_zone(zones.reverse).name.to_s
    assert_equal(1, picks.uniq.size)

    # equal area zones on the mid (multiplier 2) and top stories resolve to the unmultiplied zone
    mid_end = model.getThermalZoneByName('Zone SuperMarket Sales B end_a - Story mid').get
    top_end = model.getThermalZoneByName('Zone SuperMarket Sales B end_a - Story top').get
    assert_in_delta(mid_end.floorArea, top_end.floorArea, 0.01)
    assert_equal(top_end.name.to_s, @refrig.refrigeration_preferred_zone([mid_end, top_end]).name.to_s)

    # the larger zone is preferred regardless of story
    ground = model.getThermalZoneByName('Zone SuperMarket DryStorage B  - Story ground').get
    top = model.getThermalZoneByName('Zone SuperMarket Sales B  - Story top').get
    assert(top.floorArea > ground.floorArea)
    assert_equal(top.name.to_s, @refrig.refrigeration_preferred_zone([ground, top]).name.to_s)

    # a lower multiplier is preferred over a larger zone
    top.setMultiplier(2)
    assert_equal(ground.name.to_s, @refrig.refrigeration_preferred_zone([ground, top]).name.to_s)

    # identical zones on the same story fall back to name order
    ends = ['Zone SuperMarket Sales B end_b - Story top', 'Zone SuperMarket Sales B end_a - Story top'].map { |n| model.getThermalZoneByName(n).get }
    assert_equal('Zone SuperMarket Sales B end_a - Story top', @refrig.refrigeration_preferred_zone(ends).name.to_s)

    assert_nil(@refrig.refrigeration_preferred_zone([]))
  end
end
