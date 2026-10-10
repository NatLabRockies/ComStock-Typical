require_relative '../../../helpers/minitest_helper'

class TestHVACCreatorPostSteps < Minitest::Test
  def setup
    @model = OpenStudio::Model::Model.new
    @hvac = OpenstudioStandards::HVAC
  end

  # A hot water + condenser + chilled water plant. The block can decorate the loop specs with
  # cross-loop declarations before the spec is applied.
  def plant_spec
    spec = {
      plant_loop_info: [
        { name: 'HW Loop',
          design_info: { loop_type: 'Heating', supply_temp_f: 180.0, temp_delta_r: 20.0 },
          supply_inlet_components: [{ obj_type: 'PumpVariableSpeed', name: 'HW Pump', pump_head_fth2o: 60.0 }],
          supply_branches: [[{ obj_type: 'BoilerHotWater', name: 'Boiler', eff: 0.9 }]],
          controls: [{ spm_type: 'Scheduled', spm_temp_f: 180.0 }] },
        { name: 'Condenser Loop',
          design_info: { loop_type: 'Condenser', supply_temp_f: 70.0, temp_delta_r: 10.0 },
          supply_inlet_components: [{ obj_type: 'PumpVariableSpeed', name: 'CW Pump', pump_head_fth2o: 60.0 }],
          supply_branches: [[{ obj_type: 'CoolingTowerVariableSpeed', name: 'Tower' }]],
          controls: [{ spm_type: 'Scheduled', spm_temp_f: 70.0 }] },
        { name: 'CHW Loop',
          design_info: { loop_type: 'Cooling', supply_temp_f: 44.0, temp_delta_r: 10.0 },
          supply_inlet_components: [{ obj_type: 'PumpVariableSpeed', name: 'CHW Pump', pump_head_fth2o: 60.0 }],
          supply_branches: [[{ obj_type: 'ChillerElectricEIR', name: 'Chiller', cop: 5.5, condenser_type: 'WaterCooled', condenser_loop_name: 'Condenser Loop' }]],
          controls: [{ spm_type: 'Scheduled', spm_temp_f: 44.0 }] }
      ]
    }
    yield(spec[:plant_loop_info]) if block_given?
    spec
  end

  def hw_loop(spec_loops) = spec_loops.find { |l| l[:name] == 'HW Loop' }
  def chw_loop(spec_loops) = spec_loops.find { |l| l[:name] == 'CHW Loop' }

  def test_no_cross_loop_passes_when_absent
    @hvac.apply_hvac(@model, plant_spec)
    assert_equal(0, @model.getHeatExchangerFluidToFluids.size)
    chw = @model.getPlantLoopByName('CHW Loop').get
    assert(chw.availabilityManagers.empty?)
    spms = chw.loopTemperatureSetpointNode.setpointManagers
    assert(spms.first.to_SetpointManagerScheduled.is_initialized, 'scheduled setpoint manager remains without SWT control')
  end

  def test_waterside_economizer_adds_heat_exchanger
    spec = plant_spec { |loops| chw_loop(loops)[:waterside_economizer] = { condenser_loop_name: 'Condenser Loop', integrated: true } }
    @hvac.apply_hvac(@model, spec)
    assert_equal(1, @model.getHeatExchangerFluidToFluids.size)
    chw = @model.getPlantLoopByName('CHW Loop').get
    on_chw = chw.supplyComponents.any? { |c| c.to_HeatExchangerFluidToFluid.is_initialized }
    assert(on_chw, 'waterside economizer heat exchanger should be on the chilled water loop')
  end

  def test_two_pipe_adds_availability_managers
    spec = plant_spec do |loops|
      hw_loop(loops)[:two_pipe] = { partner_loop_name: 'CHW Loop', control_strategy: 'outdoor_air_lockout', lockout_temperature_f: 60.0 }
    end
    @hvac.apply_hvac(@model, spec)
    hw = @model.getPlantLoopByName('HW Loop').get
    chw = @model.getPlantLoopByName('CHW Loop').get
    high = hw.availabilityManagers.first.to_AvailabilityManagerHighTemperatureTurnOff
    low = chw.availabilityManagers.first.to_AvailabilityManagerLowTemperatureTurnOff
    assert(high.is_initialized, 'hot water loop gets a high-temperature lockout manager')
    assert(low.is_initialized, 'chilled water loop gets a low-temperature lockout manager')
    assert_in_delta(15.56, high.get.temperature, 0.05, 'lockout temperature converts 60 F to C')
  end

  def test_supply_water_temperature_control_installs_reset
    spec = plant_spec do |loops|
      chw_loop(loops)[:supply_water_temperature_control] = {
        strategy: 'outdoor_air',
        oat_reset: { setpoint_at_oat_low_f: 50.0, oat_low_f: 60.0, setpoint_at_oat_high_f: 44.0, oat_high_f: 80.0 }
      }
    end
    @hvac.apply_hvac(@model, spec)
    chw = @model.getPlantLoopByName('CHW Loop').get
    spm = chw.loopTemperatureSetpointNode.setpointManagers.first.to_SetpointManagerOutdoorAirReset
    assert(spm.is_initialized, 'SWT control replaces the scheduled manager with an outdoor air reset manager')
    spm = spm.get
    assert_in_delta(10.0, spm.setpointatOutdoorLowTemperature, 0.05)
    assert_in_delta(15.56, spm.outdoorLowTemperature, 0.05)
    assert_in_delta(6.67, spm.setpointatOutdoorHighTemperature, 0.05)
    assert_in_delta(26.67, spm.outdoorHighTemperature, 0.05)
  end

  def test_all_passes_forward_translate_cleanly
    spec = plant_spec do |loops|
      chw_loop(loops)[:waterside_economizer] = { condenser_loop_name: 'Condenser Loop', integrated: true }
      chw_loop(loops)[:supply_water_temperature_control] = {
        strategy: 'outdoor_air',
        oat_reset: { setpoint_at_oat_low_f: 50.0, oat_low_f: 60.0, setpoint_at_oat_high_f: 44.0, oat_high_f: 80.0 }
      }
      hw_loop(loops)[:two_pipe] = { partner_loop_name: 'CHW Loop', control_strategy: 'outdoor_air_lockout', lockout_temperature_f: 60.0 }
    end
    @hvac.apply_hvac(@model, spec)
    ft = OpenStudio::EnergyPlus::ForwardTranslator.new
    ft.translateModel(@model)
    assert_equal(0, ft.errors.size, ft.errors.map(&:logMessage).join("\n"))
  end

  def test_flatten_plant_loops_follows_secondary_loop
    loops = [{ name: 'Primary', secondary_loop: { name: 'Secondary' } }]
    flat = OpenstudioStandards::HVAC::PostSteps.flatten_plant_loops(loops)
    assert_equal(%w[Primary Secondary], flat.map { |l| l[:name] })
  end
end
