require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/hvac_system_test_helper'

# Integration test: build an HVAC system entirely from a creator spec via apply_hvac, then run a
# sizing run and a full annual EnergyPlus simulation on real geometry, and confirm the model is
# not merely wired but simulates cleanly (no severe errors, no unmet hours, nonzero energy).
#
# This test runs EnergyPlus and takes a few minutes on first run; results are cached and reused.
class TestHVACCreatorIntegrationAnnual < Minitest::Test
  def setup
    skip_unless_simulations_enabled
  end

  def test_factory_psz_runs_annual_simulation
    output_dir = "#{__dir__}/output/integration_annual"
    FileUtils.mkdir_p(output_dir)

    standard = Standard.build('90.1-2013')

    # Reuse cached results when present.
    model = nil
    if rerun_simulations? || !File.exist?("#{output_dir}/AR/run/eplusout.sql")
      model = build_and_run(standard, output_dir)
    end
    if model.nil?
      model = OpenStudio::Model::Model.new
      model.setSqlFile(OpenstudioStandards::SqlFile.sql_file_safe_load("#{output_dir}/AR/run/eplusout.sql"))
    end

    unmet_heating = OpenstudioStandards::SqlFile.model_get_annual_occupied_unmet_heating_hours(model)
    unmet_cooling = OpenstudioStandards::SqlFile.model_get_annual_occupied_unmet_cooling_hours(model)
    refute_nil(unmet_heating, 'annual simulation did not produce results')
    assert(unmet_heating <= 300.0, "too many unmet heating hours: #{unmet_heating}")
    assert(unmet_cooling <= 300.0, "too many unmet cooling hours: #{unmet_cooling}")

    total_energy = model.sqlFile.get.totalSiteEnergy
    assert(total_energy.is_initialized && total_energy.get > 0.0, 'model used no site energy')
  end

  # Build the factory system, run sizing, and run the annual simulation.
  #
  # @param standard [Standard] the standard used for the run helpers
  # @param output_dir [String] the run output directory
  # @return [OpenStudio::Model::Model] the simulated model
  def build_and_run(standard, output_dir)
    model_path = "#{__dir__}/../../../os_stds_methods/models/basic_2_story_office_no_hvac_60WWR.osm"
    model = standard.safe_load_model(model_path)
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: 'ASHRAE 169-2013-5A')

    OpenstudioStandards::HVAC.apply_hvac(model, factory_spec(model))

    assert(standard.model_run_sizing_run(model, "#{output_dir}/SR"), 'sizing run failed')
    assert(standard.model_run_simulation_and_log_errors(model, "#{output_dir}/AR"), 'annual run failed')
    model
  end

  # Build a PSZ-AC-per-zone creator spec for the model's conditioned zones.
  #
  # @param model [OpenStudio::Model::Model] the model
  # @return [Hash] the creator spec
  def factory_spec(model)
    zones = model.getThermalZones.select do |zone|
      OpenstudioStandards::ThermalZone.thermal_zone_heated?(zone) && OpenstudioStandards::ThermalZone.thermal_zone_cooled?(zone)
    end

    air_systems = []
    zone_info = []
    zones.each do |zone|
      name = zone.name.get
      air_systems << {
        name: "PSZ #{name}",
        supply_components: [
          { obj_type: 'AirLoopHVACUnitarySystem', name: "Unitary #{name}", control_type: 'Load',
            control_zone_name: name, fan_operation: { placement: 'BlowThrough' },
            components: [
              { obj_type: 'FanOnOff', name: "Fan #{name}", fan_total_eff: 0.6, pressure_rise_inh2o: 2.5 },
              { obj_type: 'CoilCoolingDXSingleSpeed', name: "DX #{name}", rated_cop: 3.5 },
              { obj_type: 'CoilHeatingGas', name: "Gas #{name}", eff_percent: 80.0 }
            ] }
        ],
        controls: [{ spm_type: 'SingleZoneReheat', control_zone_name: name, min_setpt_f: 55.0, max_setpt_f: 122.0 }]
      }
      zone_info << { zone_name: name, air_loop_name: "PSZ #{name}",
                     air_terminal_info: { air_terminal_type: 'AirTerminalSingleDuctConstantVolumeNoReheat' } }
    end

    { custom_system_type: 'Factory PSZ-AC', schema_version: '0.1.0',
      air_system_info: air_systems, zone_info: zone_info }
  end
end
