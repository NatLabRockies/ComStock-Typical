require_relative '../../../helpers/minitest_helper'

# Structural validation of a creator spec: the checks that make a malformed spec fail naming its own
# path instead of failing deep inside a builder.
class TestHVACCreatorValidation < Minitest::Test
  def setup
    @validation = OpenstudioStandards::HVAC::Validation
  end

  # A minimal well-formed spec: a hot water loop whose coil reference points backwards.
  def valid_spec
    {
      schema_version: '0.1.0',
      plant_loop_info: [
        {
          name: 'Hot Water Loop',
          design_info: { loop_type: 'Heating', supply_temp_f: 180.0, temp_delta_r: 20.0 },
          supply_branches: [[{ obj_type: 'BoilerHotWater', name: 'Boiler' }]],
          controls: [{ spm_type: 'Scheduled', name: 'HW SPM', schedule_name: 'Always 180' }]
        }
      ],
      zone_info: [
        {
          zone_name: 'Zone 1',
          zone_equipment: [{ obj_type: 'ZoneHVACBaseboardConvectiveWater', name: 'BB',
                             plant_loop_name: 'Hot Water Loop' }]
        }
      ]
    }
  end

  def check(spec)
    @validation.check(OpenstudioStandards::HVAC::ComponentFactory.deep_symbolize(spec))
  end

  def assert_error_matching(pattern, spec)
    error = assert_raises(ArgumentError) { check(spec) }
    assert_match(pattern, error.message)
    error.message
  end

  def test_valid_spec_passes_with_no_warnings
    assert_empty(check(valid_spec))
  end

  def test_unknown_top_level_key_warns
    spec = valid_spec.merge(zone_infos: [])
    warnings = check(spec)
    assert_equal(1, warnings.size)
    assert_match(/unrecognized top-level key 'zone_infos'/, warnings.first)
  end

  def test_section_must_be_an_array
    spec = valid_spec.merge(zone_info: { zone_name: 'Zone 1' })
    assert_error_matching(/zone_info must be an array/, spec)
  end

  def test_entry_must_be_an_object
    spec = valid_spec.merge(zone_info: ['Zone 1'])
    assert_error_matching(/zone_info\[0\] must be an object/, spec)
  end

  def test_missing_required_key_names_its_path
    spec = valid_spec
    spec[:plant_loop_info][0].delete(:design_info)
    assert_error_matching(/plant_loop_info\[0\] is missing required key 'design_info'/, spec)
  end

  # An existing air loop is resolved from the model, so it needs only a name.
  def test_existing_air_loop_needs_only_a_name
    spec = valid_spec.merge(air_system_info: [{ name: 'Existing AHU', existing: true }])
    assert_empty(check(spec).grep(/missing required key/))
  end

  def test_both_discriminators_is_an_error
    spec = valid_spec
    spec[:plant_loop_info][0][:supply_branches][0][0][:spm_type] = 'Scheduled'
    assert_error_matching(/sets both obj_type and spm_type/, spec)
  end

  def test_unknown_obj_type_is_an_error
    spec = valid_spec
    spec[:plant_loop_info][0][:supply_branches][0][0][:obj_type] = 'BoilerSteamPunk'
    message = assert_error_matching(/unknown obj_type 'BoilerSteamPunk'/, spec)
    assert_match(/plant_loop_info\[0\]\.supply_branches\[0\]\[0\]/, message)
  end

  def test_unknown_spm_type_is_an_error
    spec = valid_spec
    spec[:plant_loop_info][0][:controls][0][:spm_type] = 'Vibes'
    assert_error_matching(/unknown spm_type 'Vibes'/, spec)
  end

  def test_duplicate_name_is_an_error
    spec = valid_spec
    spec[:plant_loop_info] << spec[:plant_loop_info][0].dup
    assert_error_matching(/duplicate name 'Hot Water Loop'/, spec)
  end

  # A name the spec does not declare may name an object already in the model, so it only warns.
  def test_undeclared_reference_warns
    spec = valid_spec
    spec[:zone_info][0][:zone_equipment][0][:plant_loop_name] = 'Some Other Loop'
    warnings = check(spec)
    assert_equal(1, warnings.size)
    assert_match(/references 'Some Other Loop', which this spec does not declare/, warnings.first)
  end

  # Sections build in order, so a plant loop may not reference an air loop.
  def test_forward_reference_across_sections_is_an_error
    spec = valid_spec
    spec[:air_system_info] = [{ name: 'AHU 1', supply_components: [] }]
    spec[:plant_loop_info][0][:demand_components] = [{ obj_type: 'CoilCoolingWater', name: 'Coil',
                                                       air_loop_name: 'AHU 1' }]
    assert_error_matching(/references 'AHU 1', which this spec builds later \(air_system_info entry 0\)/, spec)
  end

  # Entries within a section build in listed order too.
  def test_forward_reference_within_a_section_is_an_error
    spec = valid_spec
    spec[:plant_loop_info][0][:supply_branches][0][0] = { obj_type: 'ChillerElectricEIR', name: 'Chiller',
                                                          condenser_loop_name: 'Condenser Loop' }
    spec[:plant_loop_info] << { name: 'Condenser Loop', design_info: { loop_type: 'Condenser' } }
    assert_error_matching(/references 'Condenser Loop', which this spec builds later \(plant_loop_info entry 1\)/, spec)
  end

  # The same two loops in the order they actually build are fine.
  def test_backward_reference_within_a_section_passes
    spec = valid_spec
    spec[:plant_loop_info][0][:supply_branches][0][0] = { obj_type: 'ChillerElectricEIR', name: 'Chiller',
                                                          condenser_loop_name: 'Condenser Loop' }
    spec[:plant_loop_info].unshift({ name: 'Condenser Loop', design_info: { loop_type: 'Condenser' } })
    assert_empty(check(spec))
  end

  # A secondary loop builds with its primary, so referencing it from a later loop is backwards.
  def test_secondary_loop_name_is_declared
    spec = valid_spec
    spec[:plant_loop_info][0][:secondary_loop] = { name: 'HW Secondary',
                                                   design_info: { loop_type: 'Heating' } }
    spec[:zone_info][0][:zone_equipment][0][:plant_loop_name] = 'HW Secondary'
    assert_empty(check(spec))
  end

  # A cross-loop pass runs after every loop and zone is built, so it may name a loop listed after
  # its declaring loop - the two-pipe changeover pairs a hot water loop with a chilled water one.
  def test_deferred_pass_may_reference_a_later_loop
    spec = valid_spec
    spec[:plant_loop_info][0][:two_pipe] = { control_strategy: 'outdoor_air_lockout',
                                             partner_loop_name: 'CHW Loop' }
    spec[:plant_loop_info] << { name: 'CHW Loop', design_info: { loop_type: 'Cooling' } }
    assert_empty(check(spec))
  end

  # apply_hvac runs the check, so a bad spec fails before anything is built.
  def test_apply_hvac_raises_on_an_invalid_spec
    model = OpenStudio::Model::Model.new
    spec = valid_spec
    spec[:plant_loop_info][0][:supply_branches][0][0][:obj_type] = 'NotAThing'
    error = assert_raises(ArgumentError) { OpenstudioStandards::HVAC.apply_hvac(model, spec) }
    assert_match(/unknown obj_type 'NotAThing'/, error.message)
    assert_empty(model.getPlantLoops, 'nothing should be built when the spec is invalid')
  end
end
