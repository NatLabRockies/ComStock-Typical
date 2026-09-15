require_relative '../../helpers/minitest_helper'

# Tests for building hours-of-operation plumbing and schedule-set offsets:
# parametric schedules shift with the building's weekday/weekend hours, design days
# stay anchored to the standard timing, and authored schedule-set offsets shift a
# reused occupancy definition.
class TestScheduleBuildingHours < Minitest::Test
  def setup
    @sch = OpenstudioStandards::Schedules
    @schedule_data = JSON.parse(File.read("#{File.dirname(__FILE__)}/test_schedules_data.json"), symbolize_names: true)
  end

  def new_model
    model = OpenStudio::Model::Model.new
    model.getTimestep.setNumberOfTimestepsPerHour(4)
    model
  end

  def hourly(day_sch)
    @sch.schedule_day_get_hourly_values(day_sch)
  end

  # first hour index whose value crosses the profile midpoint (the rising edge)
  def rising_edge(vals)
    mid = (vals.min + vals.max) / 2.0
    vals.index { |v| v > mid } || 0
  end

  # last hour index whose value is above the profile midpoint (the falling edge)
  def falling_edge(vals)
    mid = (vals.min + vals.max) / 2.0
    vals.rindex { |v| v > mid } || 23
  end

  def conference_default(params)
    sched = @sch.create_parametric_schedule_full(new_model, @schedule_data, 'conference occupancy', params)
    hourly(sched.to_ScheduleRuleset.get.defaultDaySchedule)
  end

  # -------------------------------------------------------------------------
  # Weekday hours shift the profile
  # -------------------------------------------------------------------------

  def test_weekday_hours_shift_profile_earlier_and_later
    standalone = conference_default({})            # st_std 8, et_std 19
    earlier = conference_default(st: 4.0, et: 15.0) # same 11h duration, shifted earlier
    later = conference_default(st: 12.0, et: 23.0)  # shifted later

    assert_operator rising_edge(earlier), :<, rising_edge(standalone), 'earlier hours should move the rising edge earlier'
    assert_operator rising_edge(later), :>, rising_edge(standalone), 'later hours should move the rising edge later'
  end

  def test_longer_duration_widens_profile
    standalone = conference_default({})
    longer = conference_default(st: 8.0, et: 23.0) # same start, longer duration

    assert_operator falling_edge(longer), :>, falling_edge(standalone), 'a longer duration should extend the falling edge later'
  end

  # -------------------------------------------------------------------------
  # Weekday vs weekend mapping
  # -------------------------------------------------------------------------

  def wk_wknd_profiles
    base = {
      start_date: '2018-01-01T00:00:00+00:00', end_date: '2018-12-31T00:00:00+00:00',
      category: 'Occupancy', type: 'parametric', base_std: 0.0, peak_std: 1.0, st_std: 8.0, et_std: 18.0,
      control_points: [['st', 'base'], ['st+1', 'peak'], ['et-1', 'peak'], ['et', 'base']]
    }
    [base.merge(name: 'wk', day_types: 'Wkdy'), base.merge(name: 'wk', day_types: 'Wknd')]
  end

  def test_weekday_weekend_mapping
    sched = @sch.create_parametric_schedule_full(new_model, wk_wknd_profiles, 'wk',
                                                 { st: 5.0, et: 9.0, wknd_st: 13.0, wknd_et: 19.0 })
    rs = sched.to_ScheduleRuleset.get

    wkdy_rule = rs.scheduleRules.find(&:applyMonday)
    wknd_rule = rs.scheduleRules.find(&:applySaturday)
    refute_nil wkdy_rule, 'expected a weekday rule'
    refute_nil wknd_rule, 'expected a weekend rule'

    wkdy_vals = hourly(wkdy_rule.daySchedule)
    wknd_vals = hourly(wknd_rule.daySchedule)

    # weekday profile is active in the morning (5-9), weekend in the afternoon (13-19)
    assert_includes 4..8, rising_edge(wkdy_vals)
    assert_includes 12..16, rising_edge(wknd_vals)
    assert_operator rising_edge(wkdy_vals), :<, rising_edge(wknd_vals)
  end

  # -------------------------------------------------------------------------
  # Design days are unaffected by building hours
  # -------------------------------------------------------------------------

  def test_design_day_unaffected_by_building_hours
    model = new_model
    sched = @sch.create_parametric_schedule_full(model, @schedule_data, 'conference occupancy', { st: 3.0, et: 9.0 })
    rs = sched.to_ScheduleRuleset.get

    default_vals = hourly(rs.defaultDaySchedule)
    summer_vals = hourly(rs.summerDesignDaySchedule)
    standalone_default = conference_default({})

    # default day shifted very early; summer design day stays at the standard timing
    assert_operator rising_edge(default_vals), :<, rising_edge(summer_vals),
                    'summer design day should not shift with building hours'
    assert_in_delta rising_edge(standalone_default), rising_edge(summer_vals), 1,
                    'summer design day rising edge should match the standalone (standard) timing'
  end

  # -------------------------------------------------------------------------
  # Authored schedule-set offsets shift a reused occupancy definition
  # -------------------------------------------------------------------------

  def test_authored_offset_applied_by_orchestrator
    # the food preparation schedule set carries start_time_offset -1.0 / end_time_offset +1.0
    model = new_model
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setName('kitchen space')
    space_type.additionalProperties.setFeature('schedule_set', 'food preparation schedule set')

    assert @sch.space_type_apply_parametric_internal_load_schedules(space_type, wkdy_start_time: 9.0, wkdy_duration: 6.0)
    people_sched = space_type.defaultScheduleSet.get.numberofPeopleSchedule.get.to_ScheduleRuleset.get
    offset_vals = hourly(people_sched.defaultDaySchedule)

    # same occupancy definition built directly at the building hours, without offset
    schedules = @sch.schedule_data(:occupancy)
    no_offset = @sch.create_parametric_schedule_full(new_model, schedules, 'food preparation occupancy',
                                                     { st: 9.0, et: 15.0 }, category: 'Occupancy')
    no_offset_vals = hourly(no_offset.to_ScheduleRuleset.get.defaultDaySchedule)

    # offset opens the kitchen earlier and closes later than the un-offset window
    assert_operator rising_edge(offset_vals), :<=, rising_edge(no_offset_vals),
                    'negative start offset should open earlier'
    assert_operator falling_edge(offset_vals), :>=, falling_edge(no_offset_vals),
                    'positive end offset should close later'
    refute_equal offset_vals, no_offset_vals, 'offset profile should differ from the un-offset profile'
  end

  # -------------------------------------------------------------------------
  # A schedule set can keep its own clock
  # -------------------------------------------------------------------------

  def test_set_that_does_not_follow_building_hours_expands_at_authored_timing
    # the guest room schedule set carries follows_building_hours: false
    model = new_model
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setName('guest room')
    space_type.additionalProperties.setFeature('schedule_set', 'guest room schedule set')
    assert @sch.space_type_apply_parametric_internal_load_schedules(space_type, wkdy_start_time: 8.0, wkdy_duration: 12.75,
                                                                     wknd_start_time: 9.0, wknd_duration: 11.0)
    people_sched = space_type.defaultScheduleSet.get.numberofPeopleSchedule.get.to_ScheduleRuleset.get
    with_hours = hourly(people_sched.defaultDaySchedule)

    authored = @sch.create_parametric_schedule_full(new_model, @sch.schedule_data(:occupancy), 'guest room occupancy',
                                                    {}, category: 'Occupancy')
    authored_vals = hourly(authored.to_ScheduleRuleset.get.defaultDaySchedule)
    assert_equal authored_vals, with_hours, 'building hours must not move a set that does not follow them'

    # and a set that does follow them still moves
    kitchen = OpenStudio::Model::SpaceType.new(model)
    kitchen.setName('kitchen')
    kitchen.additionalProperties.setFeature('schedule_set', 'food preparation schedule set')
    assert @sch.space_type_apply_parametric_internal_load_schedules(kitchen, wkdy_start_time: 8.0, wkdy_duration: 12.75)
    kitchen_sched = kitchen.defaultScheduleSet.get.numberofPeopleSchedule.get.to_ScheduleRuleset.get
    kitchen_authored = @sch.create_parametric_schedule_full(new_model, @sch.schedule_data(:occupancy), 'food preparation occupancy',
                                                            {}, category: 'Occupancy')
    refute_equal hourly(kitchen_authored.to_ScheduleRuleset.get.defaultDaySchedule), hourly(kitchen_sched.defaultDaySchedule)
  end

  def test_guest_room_keeps_its_night_under_any_building_hours
    # the room is occupied overnight and vacant by day whatever the hotel's hours, and the
    # sleep gate keeps its lights and equipment low overnight
    [[8.0, 12.75], [5.0, 17.0], [9.5, 7.25]].each do |st, dur|
      model = new_model
      space_type = OpenStudio::Model::SpaceType.new(model)
      space_type.setName('guest room')
      space_type.additionalProperties.setFeature('schedule_set', 'guest room schedule set')
      lights = OpenStudio::Model::Lights.new(OpenStudio::Model::LightsDefinition.new(model))
      lights.setSpaceType(space_type)
      assert @sch.space_type_apply_parametric_internal_load_schedules(space_type, wkdy_start_time: st, wkdy_duration: dur)
      sset = space_type.defaultScheduleSet.get
      occ = hourly(sset.numberofPeopleSchedule.get.to_ScheduleRuleset.get.defaultDaySchedule)
      ltg = hourly(sset.lightingSchedule.get.to_ScheduleRuleset.get.defaultDaySchedule)
      assert_operator occ[2], :>, 0.9, "room should be occupied at 02:00 for hours #{st} + #{dur}"
      assert_operator occ[13], :<, 0.2, "room should be vacant at 13:00 for hours #{st} + #{dur}"
      assert_operator ltg[2], :<, 0.1, "lights should be gated off at 02:00 for hours #{st} + #{dur}"
      assert_operator ltg[20], :>, 0.5, "lights should be up in the evening for hours #{st} + #{dur}"
      # the gated day runs to 24:00 at its own floor, not to OpenStudio's default of zero
      day = sset.lightingSchedule.get.to_ScheduleRuleset.get.defaultDaySchedule
      assert_equal 24.0, day.times.last.totalHours
      assert_in_delta 0.05, day.values.last, 1e-9, "the last interval of a gated day should be the lighting floor"
    end
  end
end
