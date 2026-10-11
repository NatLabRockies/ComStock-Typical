require_relative '../../../helpers/minitest_helper'
require_relative '../../../helpers/hvac_system_test_helper'

# Integration test: build a multizone VAV system with a water-cooled chilled-water plant (chiller
# + cooling tower on a condenser loop) and a hot-water plant (boiler) entirely from a creator spec
# via apply_hvac, then run a sizing run and a full annual EnergyPlus simulation and confirm it
# simulates cleanly. Exercises the chiller and the water-coil / plant-demand connections end to end.
#
# Runs EnergyPlus and takes a few minutes on first run; results are cached and reused.
class TestHVACCreatorIntegrationAnnualVAV < Minitest::Test
  def setup
    skip_unless_simulations_enabled
  end

  def test_factory_vav_chw_runs_annual_simulation
    output_dir = "#{__dir__}/output/integration_annual_vav"
    FileUtils.mkdir_p(output_dir)

    standard = Standard.build('90.1-2013')

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

  def build_and_run(standard, output_dir)
    model_path = "#{__dir__}/../../../os_stds_methods/models/basic_2_story_office_no_hvac_60WWR.osm"
    model = standard.safe_load_model(model_path)
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: 'ASHRAE 169-2013-5A')

    OpenstudioStandards::HVAC.apply_hvac(model, factory_spec(model))

    assert(standard.model_run_sizing_run(model, "#{output_dir}/SR"), 'sizing run failed')
    assert(standard.model_run_simulation_and_log_errors(model, "#{output_dir}/AR"), 'annual run failed')
    model
  end

  # Build a VAV + chilled-water + hot-water creator spec for the model's conditioned zones.
  #
  # @param model [OpenStudio::Model::Model] the model
  # @return [Hash] the creator spec
  def factory_spec(model)
    zones = model.getThermalZones.select do |zone|
      OpenstudioStandards::ThermalZone.thermal_zone_heated?(zone) && OpenstudioStandards::ThermalZone.thermal_zone_cooled?(zone)
    end

    zone_info = zones.map do |zone|
      { zone_name: zone.name.get, air_loop_name: 'VAV',
        air_terminal_info: { air_terminal_type: 'AirTerminalSingleDuctVAVReheat',
                             vav: { min_flow_frac: 0.3, damper_action: 'Reverse' },
                             reheat: { coil_info: { obj_type: 'CoilHeatingWater', plant_loop_name: 'HW Loop' } } } }
    end

    {
      custom_system_type: 'Factory VAV with chilled water',
      schema_version: '0.1.0',
      # condenser loop before chilled water loop (the chiller references it)
      plant_loop_info: [
        { name: 'CW Loop', design_info: { loop_type: 'Condenser', supply_temp_f: 85.0 },
          supply_inlet_components: [{ obj_type: 'PumpVariableSpeed', pump_head_fth2o: 60.0, vsd_control_type: 'Riding Curve' }],
          supply_branches: [[{ obj_type: 'CoolingTowerVariableSpeed', name: 'Cooling Tower' }]],
          controls: [{ spm_type: 'Scheduled', spm_temp_f: 85.0 }] },
        { name: 'CHW Loop', design_info: { loop_type: 'Cooling', supply_temp_f: 44.0 },
          supply_inlet_components: [{ obj_type: 'PumpVariableSpeed', pump_head_fth2o: 60.0, vsd_control_type: 'VSD DP Reset' }],
          supply_branches: [[{ obj_type: 'ChillerElectricEIR', name: 'Chiller', cop: 5.5,
                               condenser_loop_name: 'CW Loop', leaving_chw_temp_f: 44.0 }]],
          controls: [{ spm_type: 'Scheduled', spm_temp_f: 44.0 }] },
        { name: 'HW Loop', design_info: { loop_type: 'Heating', supply_temp_f: 180.0 },
          supply_inlet_components: [{ obj_type: 'PumpVariableSpeed', pump_head_fth2o: 60.0, vsd_control_type: 'Riding Curve' }],
          supply_branches: [[{ obj_type: 'BoilerHotWater', name: 'Boiler', eff: 0.9 }]],
          controls: [{ spm_type: 'Scheduled', spm_temp_f: 180.0 }] }
      ],
      air_system_info: [
        { name: 'VAV',
          design_info: { des_cool_sat_f: 55.0 },
          oa_control: { economizer: { type: 'FixedDryBulb', max_db_f: 65.0 } },
          supply_components: [
            { obj_type: 'CoilHeatingWater', name: 'VAV Preheat', plant_loop_name: 'HW Loop' },
            { obj_type: 'CoilCoolingWater', name: 'VAV Cooling', plant_loop_name: 'CHW Loop' },
            { obj_type: 'FanVariableVolume', name: 'VAV Fan', pressure_rise_inh2o: 4.0 }
          ],
          controls: [{ spm_type: 'Scheduled', spm_temp_f: 55.0 }] }
      ],
      zone_info: zone_info
    }
  end
end
