require_relative '../../helpers/minitest_helper'

# Every water use record names the prototype service water schedule its draw was authored
# against. The typical path replaces that schedule with the space type's own hot water
# equipment profile, derived from occupancy or traced as control points, so this pins the two
# together: at standard hours of operation the replacement must carry the same annual
# full-load hours, to within tolerance, and must not exceed the prototype's peak. A profile
# that drifts from its prototype shows up here rather than as a stock-level water heating
# change on the next run.
class TestHotWaterScheduleParity < Minitest::Test
  DATA = File.expand_path('../../../lib/openstudio-standards', __dir__)
  EFLH_TOLERANCE = 0.15
  PEAK_TOLERANCE = 0.05

  def setup
    @sch = OpenstudioStandards::Schedules
    @std = Standard.build('ComStock 90.1-2013')
  end

  def new_model
    model = OpenStudio::Model::Model.new
    model.getTimestep.setNumberOfTimestepsPerHour(4)
    model.getYearDescription.setDayofWeekforStartDay('Sunday')
    model
  end

  # all-level space type name => [schedule set name, prototype schedule name]
  def pairs
    records = JSON.parse(File.read("#{DATA}/service_water_heating/data/typical_water_use_equipment.json"), symbolize_names: true)[:space_types]
    all_level = JSON.parse(File.read("#{DATA}/space_type/data/all_level_space_types.json"), symbolize_names: true)
    sets = JSON.parse(File.read("#{DATA}/schedules/data/default_parametric_schedule_set.json"), symbolize_names: true)
    sets = sets.values.first if sets.is_a?(Hash)
    set_by_name = sets.map { |s| [s[:schedule_set_name], s] }.to_h
    out = {}
    records.each do |record|
      proto = record[:water_use_equipment].map { |e| e[:flow_rate_schedule] }.compact.first
      (record[:all_level_space_types] || []).each do |name|
        space_type = all_level.find { |a| a[:space_type_name] == name }
        next if space_type.nil? || space_type[:schedule_set_name].nil?

        set = set_by_name[space_type[:schedule_set_name]]
        next if set.nil? || set[:hot_water_equipment_schedule].nil?

        out[name] = [space_type[:schedule_set_name], proto]
      end
    end
    out
  end

  def ruleset(schedule)
    schedule.model.getScheduleRuleset(schedule.handle).get
  end

  def peak(rs)
    ([rs.defaultDaySchedule] + rs.scheduleRules.map(&:daySchedule)).flat_map(&:values).max
  end

  def test_every_hot_water_profile_matches_the_prototype_it_replaces
    failures = []
    pairs.sort.each do |name, (set_name, proto_name)|
      model = new_model
      space_type = OpenStudio::Model::SpaceType.new(model)
      space_type.setName(name)
      space_type.setStandardsSpaceType(name)
      space_type.additionalProperties.setFeature('schedule_set', set_name)
      space_type.additionalProperties.setFeature('standards_space_type', name)
      assert(@sch.space_type_apply_parametric_internal_load_schedules(space_type), "could not build schedules for #{name}")
      hot_water = space_type.defaultScheduleSet.get.hotWaterEquipmentSchedule
      if hot_water.empty?
        failures << "#{name}: schedule set '#{set_name}' produced no hot water schedule"
        next
      end
      derived = ruleset(hot_water.get)
      proto = ruleset(@std.model_add_schedule(model, proto_name))

      derived_eflh = @sch.schedule_ruleset_get_equivalent_full_load_hours(derived)
      proto_eflh = @sch.schedule_ruleset_get_equivalent_full_load_hours(proto)
      ratio = derived_eflh / proto_eflh
      note = format('%-45s %-42s eflh %6.0f vs %6.0f (%.2fx) peak %.2f vs %.2f', name, proto_name, derived_eflh, proto_eflh, ratio, peak(derived), peak(proto))
      puts note
      failures << "hours: #{note}" if (ratio - 1.0).abs > EFLH_TOLERANCE
      failures << "peak: #{note}" if peak(derived) > peak(proto) + PEAK_TOLERANCE
    end
    assert_empty(failures, "hot water profiles out of step with their prototypes:\n  #{failures.join("\n  ")}")
  end
end
