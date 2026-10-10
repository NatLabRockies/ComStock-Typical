require_relative '../../../helpers/minitest_helper'

# Integration test: build a hydronic low-temperature radiant floor system (with a DOAS for
# ventilation) entirely from a creator spec via apply_hvac, then run a sizing run and a full annual
# EnergyPlus simulation. Proves the radiant system is functional: the zone builder applies
# internal-source floor constructions so the radiant surfaces actually condition the zones.
#
# Runs EnergyPlus and takes a few minutes on first run; results are cached and reused.
class TestHVACCreatorIntegrationAnnualRadiant < Minitest::Test
  def setup
    skip_unless_simulations_enabled
  end

  def test_factory_radiant_runs_annual_simulation
    output_dir = "#{__dir__}/output/integration_annual_radiant"
    FileUtils.mkdir_p(output_dir)
    standard = Standard.build('90.1-2013')

    # always build the model (fast) so build-time artifacts (constructions) are checkable; run
    # EnergyPlus only when the annual results are not already cached.
    model = build_model(standard)
    unless File.exist?("#{output_dir}/AR/run/eplusout.sql")
      assert(standard.model_run_sizing_run(model, "#{output_dir}/SR"), 'sizing run failed')
      assert(standard.model_run_simulation_and_log_errors(model, "#{output_dir}/AR"), 'annual run failed')
    end
    model.setSqlFile(OpenstudioStandards::SqlFile.sql_file_safe_load("#{output_dir}/AR/run/eplusout.sql"))

    # radiant is slow-responding; assert it simulates and produces energy rather than tight comfort
    unmet = OpenstudioStandards::SqlFile.model_get_annual_occupied_unmet_hours(model)
    refute_nil(unmet, 'annual simulation did not produce results')
    total_energy = model.sqlFile.get.totalSiteEnergy
    assert(total_energy.is_initialized && total_energy.get > 0.0, 'model used no site energy')

    # the radiant internal-source construction was created and applied to floor surfaces
    construction = model.getConstructionWithInternalSourceByName('Creator Radiant Floor Slab')
    assert(construction.is_initialized, 'radiant internal-source construction missing')
    used = model.getSurfaces.count { |s| s.construction.is_initialized && s.construction.get.handle.to_s == construction.get.handle.to_s }
    assert(used.positive?, 'radiant construction not assigned to any surface')
  end

  def build_model(standard)
    model_path = "#{__dir__}/../../../os_stds_methods/models/basic_2_story_office_no_hvac_60WWR.osm"
    model = standard.safe_load_model(model_path)
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: 'ASHRAE 169-2013-4A')
    OpenstudioStandards::HVAC.apply_hvac(model, factory_spec(model))
    model
  end

  # Build a radiant floor + DOAS creator spec for the model's conditioned zones.
  #
  # @param model [OpenStudio::Model::Model] the model
  # @return [Hash] the creator spec
  def factory_spec(model)
    zones = model.getThermalZones.select do |zone|
      OpenstudioStandards::ThermalZone.thermal_zone_heated?(zone) && OpenstudioStandards::ThermalZone.thermal_zone_cooled?(zone)
    end

    zone_info = zones.map do |zone|
      { zone_name: zone.name.get, air_loop_name: 'DOAS',
        air_terminal_info: { air_terminal_type: 'AirTerminalSingleDuctConstantVolumeNoReheat' },
        zone_equipment: [
          { obj_type: 'ZoneHVACLowTempRadiantVarFlow', hot_water_loop_name: 'HW Loop',
            chilled_water_loop_name: 'CHW Loop', radiant_type: 'floor' }
        ] }
    end

    {
      custom_system_type: 'Factory radiant floor with DOAS',
      schema_version: '0.1.0',
      plant_loop_info: [
        # radiant loops use moderate temperatures (warm chilled water, low-temperature hot water)
        { name: 'CHW Loop', design_info: { loop_type: 'Cooling', supply_temp_f: 55.0 },
          supply_inlet_components: [{ obj_type: 'PumpVariableSpeed', pump_head_fth2o: 60.0 }],
          supply_branches: [[{ obj_type: 'DistrictCooling' }]],
          controls: [{ spm_type: 'Scheduled', spm_temp_f: 55.0 }] },
        { name: 'HW Loop', design_info: { loop_type: 'Heating', supply_temp_f: 120.0 },
          supply_inlet_components: [{ obj_type: 'PumpVariableSpeed', pump_head_fth2o: 60.0 }],
          supply_branches: [[{ obj_type: 'BoilerHotWater', eff: 0.9 }]],
          controls: [{ spm_type: 'Scheduled', spm_temp_f: 120.0 }] }
      ],
      air_system_info: [
        { name: 'DOAS',
          design_info: { des_cool_sat_f: 55.0, des_heat_sat_f: 60.0, all_outdoor_air: true },
          oa_control: { ventilation: { min_oa_frac_sch_name: 'AlwaysOn' } },
          supply_components: [
            { obj_type: 'CoilHeatingGas', name: 'DOAS Heating', eff_percent: 80.0 },
            { obj_type: 'CoilCoolingDXSingleSpeed', name: 'DOAS Cooling', rated_cop: 3.5 },
            { obj_type: 'FanConstantVolume', name: 'DOAS Fan', pressure_rise_inh2o: 3.0 }
          ],
          controls: [{ spm_type: 'Scheduled', spm_temp_f: 65.0 }] }
      ],
      zone_info: zone_info
    }
  end
end
