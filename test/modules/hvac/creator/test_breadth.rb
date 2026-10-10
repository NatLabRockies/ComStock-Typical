require_relative '../../../helpers/minitest_helper'

# Breadth test: every registered component and setpoint-manager type builds a valid object of the
# expected OpenStudio class. Failures are collected across all types so one run surfaces them all.
class TestHVACCreatorBreadth < Minitest::Test
  def setup
    @model = OpenStudio::Model::Model.new
    @ctx = OpenstudioStandards::HVAC::BuildContext.new(@model)
    @factory = OpenstudioStandards::HVAC::ComponentFactory
    @spm = OpenstudioStandards::HVAC::SetpointManagerFactory
    loop = OpenStudio::Model::PlantLoop.new(@model)
    loop.setName('Loop1')
    @ctx.register_plant_loop('Loop1', loop)
    @zone = OpenStudio::Model::ThermalZone.new(@model)
    @zone.setName('Zone 1')
  end

  # [obj_type, expected OpenStudio class (to_<name>), extra spec]
  COMPONENTS = [
    ['FanSystemModel', 'FanSystemModel', { pressure_rise_inh2o: 3.0 }],
    ['FanZoneExhaust', 'FanZoneExhaust', { pressure_rise_inh2o: 0.5 }],
    ['HumidifierSteamElectric', 'HumidifierSteamElectric', { rated_power_w: 1000.0 }],
    ['EvaporativeCoolerDirectResearchSpecial', 'EvaporativeCoolerDirectResearchSpecial', { design_effectiveness: 0.9 }],
    ['CoilHeatingDesuperheater', 'CoilHeatingDesuperheater', { reclaim_eff: 0.3 }],
    ['HeatExchangerAirToAirSensibleAndLatent', 'HeatExchangerAirToAirSensibleAndLatent', {}],
    ['CoilHeatingDXSingleSpeed', 'CoilHeatingDXSingleSpeed', { rated_cop: 3.5 }],
    ['CoilCoolingDXTwoSpeed', 'CoilCoolingDXTwoSpeed', { hs_rated_cop: 3.5, ls_rated_cop: 3.6 }],
    ['CoilCoolingDXTwoStageWithHumidityControlMode', 'CoilCoolingDXTwoStageWithHumidityControlMode', {}],
    ['CoilCoolingWaterToAirHeatPump', 'CoilCoolingWaterToAirHeatPumpEquationFit', { plant_loop_name: 'Loop1', rated_cop: 4.0 }],
    ['CoilCoolingWaterToAirHeatPumpVariableSpeed', 'CoilCoolingWaterToAirHeatPumpVariableSpeedEquationFit', { plant_loop_name: 'Loop1' }],
    ['CoilHeatingWaterToAirHeatPump', 'CoilHeatingWaterToAirHeatPumpEquationFit', { plant_loop_name: 'Loop1', rated_cop: 4.0 }],
    ['ZoneHVACWaterToAirHeatPump', 'ZoneHVACWaterToAirHeatPump', { condenser_loop_name: 'Loop1' }],
    ['ZoneHVACPackagedTerminalHeatPump', 'ZoneHVACPackagedTerminalHeatPump', { fan_type: 'Cycling' }],
    ['HeaderedPumpsVariableSpeed', 'HeaderedPumpsVariableSpeed', { num_pumps: 2, pump_head_fth2o: 60.0 }],
    ['HeaderedPumpsConstantSpeed', 'HeaderedPumpsConstantSpeed', { num_pumps: 2 }],
    ['CoolingTowerSingleSpeed', 'CoolingTowerSingleSpeed', { num_cells: 2 }],
    ['CoolingTowerTwoSpeed', 'CoolingTowerTwoSpeed', { sizing_factor: 1.1 }],
    ['FluidCoolerSingleSpeed', 'FluidCoolerSingleSpeed', {}],
    ['FluidCoolerTwoSpeed', 'FluidCoolerTwoSpeed', {}],
    ['EvaporativeFluidCoolerSingleSpeed', 'EvaporativeFluidCoolerSingleSpeed', {}],
    ['EvaporativeFluidCoolerTwoSpeed', 'EvaporativeFluidCoolerTwoSpeed', {}],
    ['HeatExchangerFluidToFluid', 'HeatExchangerFluidToFluid', { control_type: 'UncontrolledOn' }],
    ['PlantComponentTemperatureSource', 'PlantComponentTemperatureSource', { source_temp_c: 12.0 }],
    ['HeatPumpPlantLoopEIRCooling', 'HeatPumpPlantLoopEIRCooling', { condenser_type: 'WaterSource', cop: 3.5 }],
    ['HeatPumpPlantLoopEIRHeating', 'HeatPumpPlantLoopEIRHeating', { condenser_type: 'AirSource', cop: 3.0 }],
    ['HeatPumpWaterToWaterEquationFitCooling', 'HeatPumpWaterToWaterEquationFitCooling', {}],
    ['HeatPumpWaterToWaterEquationFitHeating', 'HeatPumpWaterToWaterEquationFitHeating', {}],
    ['ThermalStorageIceDetailed', 'ThermalStorageIceDetailed', { capacity_gj: 5.0 }],
    ['ZoneHVACIdealLoadsAirSystem', 'ZoneHVACIdealLoadsAirSystem', { max_heat_f: 122.0 }],
    ['ZoneVentilationDesignFlowRate', 'ZoneVentilationDesignFlowRate', { ventilation_type: 'Exhaust', flow_rate: 0.1 }],
    ['ZoneHVACHighTemperatureRadiant', 'ZoneHVACHighTemperatureRadiant', { heating_type: 'NaturalGas' }],
    ['AirSourceHeatPump', 'PlantComponentUserDefined', { plant_loop_name: 'Loop1', cop: 3.5 }],
    ['ZoneHVACUnitVentilator', 'ZoneHVACUnitVentilator', {}],
    ['ZoneHVACEnergyRecoveryVentilator', 'ZoneHVACEnergyRecoveryVentilator', {}],
    ['ZoneHVACWindowAirConditioner', 'ZoneHVACPackagedTerminalAirConditioner', { eer: 10.0, shr: 0.7 }]
  ].freeze

  SETPOINT_MANAGERS = [
    ['ScheduledDual', 'SetpointManagerScheduledDualSetpoint', { spm_lo_temp_f: 55.0, spm_hi_temp_f: 75.0 }],
    ['MixedAir', 'SetpointManagerMixedAir', {}],
    ['Warmest', 'SetpointManagerWarmest', { max_setpt_f: 65.0 }],
    ['SingleZoneCooling', 'SetpointManagerSingleZoneCooling', { control_zone_name: 'Zone 1', min_setpt_f: 55.0 }],
    ['SingleZoneHeating', 'SetpointManagerSingleZoneHeating', { control_zone_name: 'Zone 1', max_setpt_f: 120.0 }],
    ['OutdoorAirReset', 'SetpointManagerOutdoorAirReset', { oat_low_f: 20.0, setpoint_at_oat_low_f: 150.0, oat_high_f: 70.0, setpoint_at_oat_high_f: 120.0 }],
    ['FollowOutdoorAir', 'SetpointManagerFollowOutdoorAirTemperature', { ref_temp: 'OutdoorAirWetBulb', offset_temp_r: 5.0 }]
  ].freeze

  def test_all_components_build
    failures = []
    COMPONENTS.each do |obj_type, klass, extra|
      begin
        object = @factory.build({ obj_type: obj_type }.merge(extra), @ctx)
        failures << "#{obj_type}: not a #{klass}" unless object.public_send("to_#{klass}").is_initialized
      rescue StandardError => e
        failures << "#{obj_type}: #{e.class} #{e.message}"
      end
    end
    assert(failures.empty?, "component build failures:\n#{failures.join("\n")}")
  end

  def test_all_setpoint_managers_build
    failures = []
    SETPOINT_MANAGERS.each do |spm_type, klass, extra|
      begin
        manager = @spm.build({ spm_type: spm_type }.merge(extra), @ctx)
        failures << "#{spm_type}: not a #{klass}" unless manager.public_send("to_#{klass}").is_initialized
      rescue StandardError => e
        failures << "#{spm_type}: #{e.class} #{e.message}"
      end
    end
    assert(failures.empty?, "setpoint manager build failures:\n#{failures.join("\n")}")
  end

  def test_registry_covers_schema_enum
    schema = JSON.parse(File.read(@factory::SCHEMA_PATH))
    enum = schema['$defs']['hvacComponent']['properties']['obj_type']['enum']
    unregistered = enum.reject { |t| @factory.registered?(t) }
    assert(unregistered.empty?, "every schema obj_type must be registered; missing: #{unregistered.join(', ')}")
  end
end
