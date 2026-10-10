require_relative '../../../helpers/minitest_helper'

class TestHVACCreatorApplyHvac < Minitest::Test
  def setup
    @model = OpenStudio::Model::Model.new
    @hvac = OpenstudioStandards::HVAC
    @zone = OpenStudio::Model::ThermalZone.new(@model)
    @zone.setName('Zone 1')
  end

  def psz_spec
    {
      schema_version: '0.1.0',
      custom_system_type: 'Test PSZ',
      description: 'A single-zone packaged system for testing.',
      air_system_info: [
        {
          name: 'PSZ-AC',
          supply_components: [
            { obj_type: 'AirLoopHVACUnitarySystem', name: 'Unitary', control_zone_name: 'Zone 1',
              components: [
                { obj_type: 'FanOnOff', name: 'Fan' },
                { obj_type: 'CoilCoolingDXSingleSpeed', name: 'DX', rated_cop: 3.5 },
                { obj_type: 'CoilHeatingGas', name: 'Gas', eff_percent: 80.0 }
              ] }
          ],
          controls: [{ spm_type: 'Scheduled', spm_temp_f: 55.0 }]
        }
      ],
      zone_info: [
        { zone_name: 'Zone 1', air_loop_name: 'PSZ-AC',
          air_terminal_info: { air_terminal_type: 'AirTerminalSingleDuctConstantVolumeNoReheat', max_airflow_cfm: 500.0 } }
      ]
    }
  end

  def test_builds_complete_psz_system
    @hvac.apply_hvac(@model, psz_spec)
    # air loop created
    assert_equal(1, @model.getAirLoopHVACs.size)
    air_loop = @model.getAirLoopHVACs.first
    assert_equal('PSZ-AC', air_loop.name.get)
    # zone attached to the loop
    assert(@zone.airLoopHVAC.is_initialized)
    assert_equal(air_loop, @zone.airLoopHVAC.get)
    # unitary control zone resolved
    unitary = @model.getAirLoopHVACUnitarySystems.first
    assert(unitary.controllingZoneorThermostatLocation.is_initialized)
    assert_equal('Zone 1', unitary.controllingZoneorThermostatLocation.get.name.get)
  end

  def test_writes_building_properties
    @hvac.apply_hvac(@model, psz_spec)
    props = @model.getBuilding.additionalProperties
    assert_equal('Test PSZ', props.getFeatureAsString('custom_system_type').get)
    assert_equal('0.1.0', props.getFeatureAsString('hvac_schema_version').get)
  end

  def test_returns_context_with_registered_loop
    context = @hvac.apply_hvac(@model, psz_spec)
    assert_equal('PSZ-AC', context.air_loop('PSZ-AC').name.get)
  end

  def test_plant_and_air_build_in_order
    spec = {
      plant_loop_info: [
        { name: 'HW Loop', design_info: { loop_type: 'Heating', supply_temp_f: 180.0 },
          supply_inlet_components: [{ obj_type: 'PumpVariableSpeed', pump_head_fth2o: 60.0 }],
          supply_branches: [[{ obj_type: 'BoilerHotWater', eff: 0.9 }]],
          controls: [{ spm_type: 'Scheduled', spm_temp_f: 180.0 }] }
      ],
      air_system_info: [
        { name: 'AHU', supply_components: [{ obj_type: 'FanVariableVolume', name: 'SF' }],
          controls: [{ spm_type: 'Scheduled', spm_temp_f: 55.0 }] }
      ]
    }
    context = @hvac.apply_hvac(@model, spec)
    assert_equal(1, @model.getPlantLoops.size)
    assert_equal(1, @model.getAirLoopHVACs.size)
    assert(context.plant_loop('HW Loop'))
    assert(context.air_loop('AHU'))
  end

  def test_ems_info_builds_objects
    @hvac.apply_hvac(@model, {
                       ems_info: [{
                         sensors: [{ name: 'OAT', keyname: 'Environment', variable: 'Site Outdoor Air Drybulb Temperature' }],
                         programs: [{ name: 'Prog', body: 'SET x = OAT' }],
                         calling_managers: [{ name: 'CM', calling_point: 'BeginTimestepBeforePredictor', program_names: ['Prog'] }]
                       }]
                     })
    assert_equal(1, @model.getEnergyManagementSystemSensors.size)
    assert_equal(1, @model.getEnergyManagementSystemPrograms.size)
    assert_equal(1, @model.getEnergyManagementSystemProgramCallingManagers.size)
  end

  def test_accepts_string_keyed_spec
    @hvac.apply_hvac(@model, JSON.parse(psz_spec.to_json))
    assert_equal(1, @model.getAirLoopHVACs.size)
    assert(@zone.airLoopHVAC.is_initialized)
  end
end
