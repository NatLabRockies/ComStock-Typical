module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    module ComponentFactory
      # Registry mapping an +obj_type+ to the builder that creates it.
      #
      # Each builder is a +->(spec, context)+ lambda returning the OpenStudio object with its
      # type-specific fields set. Builders are added here as they are implemented; every type in
      # the schema +obj_type+ enum is expected to have an entry. Types not yet implemented are
      # simply absent, and {ComponentFactory.build} raises a clear error for them.
      COMPONENT_BUILDERS = {
        'FanOnOff' => ->(spec, context) { ComponentFactory.build_fan_on_off(spec, context) },
        'FanConstantVolume' => ->(spec, context) { ComponentFactory.build_fan_constant_volume(spec, context) },
        'FanVariableVolume' => ->(spec, context) { ComponentFactory.build_fan_variable_volume(spec, context) },
        'CoilHeatingGas' => ->(spec, context) { ComponentFactory.build_coil_heating_gas(spec, context) },
        'CoilHeatingElectric' => ->(spec, context) { ComponentFactory.build_coil_heating_electric(spec, context) },
        'PumpVariableSpeed' => ->(spec, context) { ComponentFactory.build_pump_variable_speed(spec, context) },
        'PumpConstantSpeed' => ->(spec, context) { ComponentFactory.build_pump_constant_speed(spec, context) },
        'BoilerHotWater' => ->(spec, context) { ComponentFactory.build_boiler_hot_water(spec, context) },
        'CoilCoolingDXSingleSpeed' => ->(spec, context) { ComponentFactory.build_coil_cooling_dx_single_speed(spec, context) },
        'CoilCoolingDXVariableSpeed' => ->(spec, context) { ComponentFactory.build_coil_cooling_dx_variable_speed(spec, context) },
        'CoilCoolingDXMultiSpeed' => ->(spec, context) { ComponentFactory.build_coil_cooling_dx_multi_speed(spec, context) },
        'CoilHeatingDXMultiSpeed' => ->(spec, context) { ComponentFactory.build_coil_heating_dx_multi_speed(spec, context) },
        'AirLoopHVACUnitarySystem' => ->(spec, context) { ComponentFactory.build_unitary_system(spec, context) },
        'ZoneHVACBaseboardConvectiveElectric' => ->(spec, context) { ComponentFactory.build_baseboard_convective_electric(spec, context) },
        'ZoneHVACBaseboardConvectiveWater' => ->(spec, context) { ComponentFactory.build_baseboard_convective_water(spec, context) },
        'ZoneHVACFourPipeFanCoil' => ->(spec, context) { ComponentFactory.build_four_pipe_fan_coil(spec, context) },
        'ZoneHVACUnitHeater' => ->(spec, context) { ComponentFactory.build_unit_heater(spec, context) },
        'ZoneHVACPackagedTerminalAirConditioner' => ->(spec, context) { ComponentFactory.build_ptac(spec, context) },
        'CoilCoolingWater' => ->(spec, context) { ComponentFactory.build_coil_cooling_water(spec, context) },
        'CoilHeatingWater' => ->(spec, context) { ComponentFactory.build_coil_heating_water(spec, context) },
        'DistrictCooling' => ->(spec, context) { ComponentFactory.build_district(spec, context) },
        'DistrictHeatingWater' => ->(spec, context) { ComponentFactory.build_district(spec, context) },
        'DistrictHeatingSteam' => ->(spec, context) { ComponentFactory.build_district(spec, context) },
        'ChillerElectricEIR' => ->(spec, context) { ComponentFactory.build_chiller_electric_eir(spec, context) },
        'CoolingTowerVariableSpeed' => ->(spec, context) { ComponentFactory.build_cooling_tower_variable_speed(spec, context) },
        'FanSystemModel' => ->(spec, context) { ComponentFactory.build_fan_system_model(spec, context) },
        'FanZoneExhaust' => ->(spec, context) { ComponentFactory.build_fan_zone_exhaust(spec, context) },
        'HumidifierSteamElectric' => ->(spec, context) { ComponentFactory.build_humidifier_steam_electric(spec, context) },
        'EvaporativeCoolerDirectResearchSpecial' => ->(spec, context) { ComponentFactory.build_evaporative_cooler_direct(spec, context) },
        'CoilHeatingDesuperheater' => ->(spec, context) { ComponentFactory.build_coil_heating_desuperheater(spec, context) },
        'HeatExchangerAirToAirSensibleAndLatent' => ->(spec, context) { ComponentFactory.build_hx_air_to_air(spec, context) },
        'CoilHeatingDXSingleSpeed' => ->(spec, context) { ComponentFactory.build_coil_heating_dx_single_speed(spec, context) },
        'CoilCoolingDXTwoSpeed' => ->(spec, context) { ComponentFactory.build_coil_cooling_dx_two_speed(spec, context) },
        'CoilCoolingDXTwoStageWithHumidityControlMode' => ->(spec, context) { ComponentFactory.build_coil_cooling_dx_two_stage(spec, context) },
        'CoilCoolingWaterToAirHeatPump' => ->(spec, context) { ComponentFactory.build_coil_cooling_wahp(spec, context) },
        'CoilCoolingWaterToAirHeatPumpVariableSpeed' => ->(spec, context) { ComponentFactory.build_coil_cooling_wahp(spec, context) },
        'CoilHeatingWaterToAirHeatPump' => ->(spec, context) { ComponentFactory.build_coil_heating_wahp(spec, context) },
        'ZoneHVACWaterToAirHeatPump' => ->(spec, context) { ComponentFactory.build_zone_wahp(spec, context) },
        'ZoneHVACPackagedTerminalHeatPump' => ->(spec, context) { ComponentFactory.build_pthp(spec, context) },
        'HeaderedPumpsVariableSpeed' => ->(spec, context) { ComponentFactory.build_headered_pumps(spec, context) },
        'HeaderedPumpsConstantSpeed' => ->(spec, context) { ComponentFactory.build_headered_pumps(spec, context) },
        'CoolingTowerSingleSpeed' => ->(spec, context) { ComponentFactory.build_cooling_tower_single_speed(spec, context) },
        'CoolingTowerTwoSpeed' => ->(spec, context) { ComponentFactory.build_cooling_tower_two_speed(spec, context) },
        'FluidCoolerSingleSpeed' => ->(spec, context) { ComponentFactory.build_fluid_cooler_single_speed(spec, context) },
        'FluidCoolerTwoSpeed' => ->(spec, context) { ComponentFactory.build_fluid_cooler_two_speed(spec, context) },
        'EvaporativeFluidCoolerSingleSpeed' => ->(spec, context) { ComponentFactory.build_evaporative_fluid_cooler(spec, context) },
        'EvaporativeFluidCoolerTwoSpeed' => ->(spec, context) { ComponentFactory.build_evaporative_fluid_cooler(spec, context) },
        'HeatExchangerFluidToFluid' => ->(spec, context) { ComponentFactory.build_hx_fluid_to_fluid(spec, context) },
        'PlantComponentTemperatureSource' => ->(spec, context) { ComponentFactory.build_plant_temperature_source(spec, context) },
        'HeatPumpPlantLoopEIRCooling' => ->(spec, context) { ComponentFactory.build_hp_plant_loop_eir(spec, context) },
        'HeatPumpPlantLoopEIRHeating' => ->(spec, context) { ComponentFactory.build_hp_plant_loop_eir(spec, context) },
        'HeatPumpWaterToWaterEquationFitCooling' => ->(spec, context) { ComponentFactory.build_hp_water_to_water(spec, context) },
        'HeatPumpWaterToWaterEquationFitHeating' => ->(spec, context) { ComponentFactory.build_hp_water_to_water(spec, context) },
        'ThermalStorageIceDetailed' => ->(spec, context) { ComponentFactory.build_ice_storage(spec, context) },
        'ZoneHVACIdealLoadsAirSystem' => ->(spec, context) { ComponentFactory.build_ideal_loads(spec, context) },
        'ZoneVentilationDesignFlowRate' => ->(spec, context) { ComponentFactory.build_zone_ventilation(spec, context) },
        'ZoneHVACHighTemperatureRadiant' => ->(spec, context) { ComponentFactory.build_high_temperature_radiant(spec, context) },
        'ZoneHVACTerminalUnitVariableRefrigerantFlow' => ->(spec, context) { ComponentFactory.build_vrf_terminal(spec, context) },
        'AirLoopHVACUnitaryHeatCoolVAVChangeoverBypass' => ->(spec, context) { ComponentFactory.build_unitary_changeover_bypass(spec, context) },
        'CoilSystemCoolingWaterHXAssist' => ->(spec, context) { ComponentFactory.build_coil_system_cooling_water_hx_assist(spec, context) },
        'ZoneHVACLowTemperatureRadiantElectric' => ->(spec, context) { ComponentFactory.build_low_temperature_radiant_electric(spec, context) },
        'ZoneHVACLowTempRadiantVarFlow' => ->(spec, context) { ComponentFactory.build_low_temp_radiant_var_flow(spec, context) },
        'AirSourceHeatPump' => ->(spec, context) { ComponentFactory.build_air_source_heat_pump(spec, context) },
        'ZoneHVACUnitVentilator' => ->(spec, context) { ComponentFactory.build_unit_ventilator(spec, context) },
        'ZoneHVACEnergyRecoveryVentilator' => ->(spec, context) { ComponentFactory.build_energy_recovery_ventilator(spec, context) },
        'ZoneHVACWindowAirConditioner' => ->(spec, context) { ComponentFactory.build_window_ac(spec, context) }
      }.freeze
    end
  end
end
