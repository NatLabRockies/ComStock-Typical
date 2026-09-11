# Second half of the Phase 3 baseline: build a custom building from a specification once per
# registered template, with HVAC off so no sizing run is needed.
#
# Two things the specification has to get right or the template fails for reasons that have
# nothing to do with the code under test. The climate zone has to belong to the template's own
# family, since DEER is keyed on CEC zones and the ASHRAE family on ASHRAE ones. And the building
# and space type names have to be ones the template carries, so they are taken from the
# template's own space_types table; the later DEER vintages have no table of their own, so they
# borrow from the newest sibling in their family that does.
STDOUT.sync = true
require 'openstudio'
require 'json'
ROOT = ENV['CHECK_ROOT'] || File.expand_path('..', __dir__)
OUT  = ENV['SMOKE_OUT'] || "#{Dir.pwd}/spec_smoke_results.txt"
$LOAD_PATH.unshift("#{ROOT}/lib")
require(File.exist?("#{ROOT}/lib/comstock-typical.rb") ? 'comstock-typical' : 'openstudio-standards')

UNOCCUPIED = %w[Plenum Attic Any].freeze

def climate_zone_for(template)
  template.include?('DEER') ? 'CEC T24-CEC9' : 'ASHRAE 169-2013-4A'
end

def pairs_for(std)
  (std.standards_data['space_types'] || [])
    .map { |r| [r['building_type'], r['space_type']] }
    .reject { |bt, st| bt.nil? || st.nil? || UNOCCUPIED.include?(bt) || UNOCCUPIED.include?(st) }
    .group_by(&:first).map { |_bt, list| list.first }.first(2)
end

templates = Standard::STANDARDS_LIST.keys.sort
# a donor per family, for templates that carry no space_types table of their own
donors = {}
templates.each do |t|
  family = t.include?('DEER') ? 'DEER' : 'ASHRAE'
  next if donors.key?(family)
  p = pairs_for(Standard.build(t))
  donors[family] = p if p.size >= 2
end

rows = []
templates.each do |template|
  std = Standard.build(template)
  family = template.include?('DEER') ? 'DEER' : 'ASHRAE'
  pairs = pairs_for(std)
  borrowed = false
  if pairs.size < 2
    pairs = donors[family]
    borrowed = true
  end
  if pairs.nil? || pairs.size < 2
    rows << format('SKIP  %-28s no usable building types in the %s family', template, family)
    next
  end
  cz = climate_zone_for(template)
  spec = {
    name: "Smoke #{template}",
    template: template,
    climate_zone: cz,
    space_type_ratios: [
      { building_type: pairs[0][0], space_type: pairs[0][1], ratio: 0.6, default: true },
      { building_type: pairs[1][0], space_type: pairs[1][1], ratio: 0.4 }
    ],
    form: { total_bldg_floor_area: 20000.0, num_stories_above_grade: 1, ns_to_ew_ratio: 2.0, wwr: 0.3, floor_height: 12.0 },
    typical_options: { add_hvac: false }
  }
  model = OpenStudio::Model::Model.new
  begin
    result = OpenstudioStandards::CreateTypical.create_custom_building_from_spec(model, spec)
    label = "#{pairs[0].join('/')} + #{pairs[1].join('/')}#{borrowed ? ' (borrowed)' : ''}"
    rows << if result && model.getSpaceTypes.size == 2
              format('PASS  %-28s %-18s %s', template, cz, label)
            else
              format('FAIL  %-28s %-18s result=%p space_types=%d (%s)', template, cz, result,
                     model.getSpaceTypes.size, label)
            end
  rescue StandardError => e
    rows << format('FAIL  %-28s %-18s %s: %s', template, cz, e.class, e.message.to_s.lines.first.to_s.strip)
  end
end

rows << ''
rows << "#{rows.count { |r| r.start_with?('PASS') }} passed, " \
        "#{rows.count { |r| r.start_with?('FAIL') }} failed, " \
        "#{rows.count { |r| r.start_with?('SKIP') }} skipped"
File.write(OUT, rows.join("\n") + "\n")
puts rows.join("\n")
