require_relative '../../helpers/minitest_helper'

# Every CBECS HVAC system type, composed on a real typical building, for one template per family
# and era. The creator's composers are driven here by the strings create_cbecs_hvac_system
# forwards from ComStock's HVAC type list, not by hand-written fixtures: the upstream cutover
# found that the data files reach cooling types and name collisions the synthetic tests never
# supplied, so this is the fork's stand-in for the prototype suites it does not carry.
#
# No sizing run: each system is built, checked for serving every conditioned zone, and dropped.
class TestCBECSHVACSweep < Minitest::Test
  TEMPLATES = {
    '90.1-2004' => 'ASHRAE 169-2013-4A',
    '90.1-2019' => 'ASHRAE 169-2013-4A',
    'DOE Ref Pre-1980' => 'ASHRAE 169-2013-4A',
    'ComStock 90.1-2013' => 'ASHRAE 169-2013-4A',
    'ComStock DEER 2003' => 'CEC T24-CEC9'
  }.freeze

  UNOCCUPIED = ['Plenum', 'Attic', 'Any'].freeze

  # The system types create_cbecs_hvac_system dispatches on, read from its case statement so a
  # type added there is swept without touching this test.
  def self.cbecs_system_types
    source = File.read(File.expand_path('../../../lib/openstudio-standards/hvac/create_cbecs_hvac_system.rb', __dir__))
    types = source.scan(/^\s+when '([^']+)'/).flatten.uniq
    raise 'no CBECS system types found' if types.empty?

    types
  end

  # Two space types the template carries, for a two-type bar building.
  def space_type_pairs(std)
    (std.standards_data['space_types'] || [])
      .map { |r| [r['building_type'], r['space_type']] }
      .reject { |bt, st| bt.nil? || st.nil? || UNOCCUPIED.include?(bt) || UNOCCUPIED.include?(st) }
      .group_by(&:first).map { |_bt, list| list.first }.first(2)
  end

  # A typical building with loads, schedules and thermostats but no HVAC.
  def base_model(template, climate_zone)
    std = Standard.build(template)
    pairs = space_type_pairs(std)
    raise "#{template} carries fewer than two usable space types" if pairs.size < 2

    spec = {
      name: "CBECS sweep #{template}",
      template: template,
      climate_zone: climate_zone,
      space_type_ratios: [
        { building_type: pairs[0][0], space_type: pairs[0][1], ratio: 0.6, default: true },
        { building_type: pairs[1][0], space_type: pairs[1][1], ratio: 0.4 }
      ],
      form: { total_bldg_floor_area: 20000.0, num_stories_above_grade: 2, ns_to_ew_ratio: 2.0, wwr: 0.3, floor_height: 12.0 },
      typical_options: { add_hvac: false }
    }
    model = OpenStudio::Model::Model.new
    assert(OpenstudioStandards::CreateTypical.create_custom_building_from_spec(model, spec), "#{template}: base building did not build")
    [model, std]
  end

  def conditioned_zones(model)
    model.getThermalZones.select do |zone|
      OpenstudioStandards::ThermalZone.thermal_zone_heated?(zone) || OpenstudioStandards::ThermalZone.thermal_zone_cooled?(zone)
    end
  end

  def zone_served?(zone)
    zone.airLoopHVAC.is_initialized || !zone.equipment.empty?
  end

  def sweep(template, climate_zone)
    model, std = base_model(template, climate_zone)
    zones = conditioned_zones(model)
    refute_empty(zones, "#{template}: no conditioned zones to serve")
    problems = []
    self.class.cbecs_system_types.each do |system_type|
      trial = model.clone(true).to_Model
      trial_zones = trial.getThermalZones.select { |z| zones.any? { |zone| zone.name.to_s == z.name.to_s } }
      begin
        built = OpenstudioStandards::HVAC.create_cbecs_hvac_system(trial, std, system_type, trial_zones)
        unless built
          problems << "#{system_type}: create_cbecs_hvac_system returned false"
          next
        end
        unserved = trial_zones.reject { |zone| zone_served?(zone) }.map { |zone| zone.name.to_s }
        problems << "#{system_type}: zones without equipment or an air loop: #{unserved.join(', ')}" unless unserved.empty?
      rescue StandardError => e
        problems << "#{system_type}: #{e.class}: #{e.message.to_s.lines.first.to_s.strip}"
      end
    end
    assert_empty(problems, "#{template}:\n  #{problems.join("\n  ")}")
  end

  TEMPLATES.each do |template, climate_zone|
    define_method("test_every_cbecs_system_composes_on_#{template.downcase.gsub(/[^a-z0-9]+/, '_')}") do
      sweep(template, climate_zone)
    end
  end
end
