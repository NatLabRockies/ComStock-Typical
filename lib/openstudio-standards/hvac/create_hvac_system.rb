module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Create HVAC Systems

    # Creates a hot water loop with a boiler, district heating, or a water-to-water heat pump and adds it to the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param boiler_fuel_type [String] valid choices are Electricity, NaturalGas, Propane, PropaneGas, FuelOilNo1, FuelOilNo2,
    #   DistrictHeating, DistrictHeatingWater, DistrictHeatingSteam, HeatPump
    # @param ambient_loop [OpenStudio::Model::PlantLoop] The condenser loop for the heat pump. Only used when boiler_fuel_type is HeatPump.
    # @param system_name [String] the name of the system, or nil in which case it will be defaulted
    # @param dsgn_sup_wtr_temp [Double] design supply water temperature in degrees Fahrenheit, default 180F
    # @param dsgn_sup_wtr_temp_delt [Double] design supply-return water temperature difference in degrees Rankine, default 20R
    # @param pump_spd_ctrl [String] pump speed control type, Constant or Variable (default)
    # @param pump_tot_hd [Double] pump head in ft H2O
    # @param boiler_draft_type [String] Boiler type Condensing, MechanicalNoncondensing, Natural (default)
    # @param boiler_eff_curve_temp_eval_var [String] LeavingBoiler or EnteringBoiler temperature for the boiler efficiency curve
    # @param boiler_lvg_temp_dsgn [Double] boiler leaving design temperature in degrees Fahrenheit
    # @param boiler_out_temp_lmt [Double] boiler outlet temperature limit in degrees Fahrenheit
    # @param boiler_max_plr [Double] boiler maximum part load ratio
    # @param boiler_sizing_factor [Double] boiler oversizing factor
    # @return [OpenStudio::Model::PlantLoop] the resulting hot water loop
    def self.model_add_hw_loop(model,
                               boiler_fuel_type,
                               ambient_loop: nil,
                               system_name: 'Hot Water Loop',
                               dsgn_sup_wtr_temp: 180.0,
                               dsgn_sup_wtr_temp_delt: 20.0,
                               pump_spd_ctrl: 'Variable',
                               pump_tot_hd: nil,
                               boiler_draft_type: nil,
                               boiler_eff_curve_temp_eval_var: nil,
                               boiler_lvg_temp_dsgn: nil,
                               boiler_out_temp_lmt: nil,
                               boiler_max_plr: nil,
                               boiler_sizing_factor: nil)
      Composers.hw_loop(model,
                        boiler_fuel_type,
                        ambient_loop: ambient_loop,
                        system_name: system_name,
                        dsgn_sup_wtr_temp: dsgn_sup_wtr_temp,
                        dsgn_sup_wtr_temp_delt: dsgn_sup_wtr_temp_delt,
                        pump_spd_ctrl: pump_spd_ctrl,
                        pump_tot_hd: pump_tot_hd,
                        boiler_draft_type: boiler_draft_type,
                        boiler_eff_curve_temp_eval_var: boiler_eff_curve_temp_eval_var,
                        boiler_lvg_temp_dsgn: boiler_lvg_temp_dsgn,
                        boiler_out_temp_lmt: boiler_out_temp_lmt,
                        boiler_max_plr: boiler_max_plr,
                        boiler_sizing_factor: boiler_sizing_factor)
    end

    # Creates a chilled water loop and adds it to the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param system_name [String] the name of the system, or nil in which case it will be defaulted
    # @param cooling_fuel [String] cooling fuel. Valid choices are: Electricity, DistrictCooling
    # @param dsgn_sup_wtr_temp [Double] design supply water temperature in degrees Fahrenheit, default 44F
    # @param dsgn_sup_wtr_temp_delt [Double] design supply-return water temperature difference in degrees Rankine, default 10R
    # @param chw_pumping_configuration [String] valid choices are 'constant primary', 'constant primary variable secondary common pipe', 'constant primary variable secondary heat exchanger'
    # @param chiller_cooling_type [String] valid choices are AirCooled, WaterCooled
    # @param chiller_condenser_type [String] valid choices are WithCondenser, WithoutCondenser, nil
    # @param chiller_compressor_type [String] valid choices are Centrifugal, Reciprocating, Rotary Screw, Scroll, nil
    # @param num_chillers [Integer] the number of chillers
    # @param condenser_water_loop [OpenStudio::Model::PlantLoop] optional condenser water loop for water-cooled chillers.
    #   If this is not passed in, the chillers will be air cooled.
    # @param waterside_economizer [String] Options are 'none', 'integrated', 'non-integrated'.
    #   If 'integrated' will add a heat exchanger to the supply inlet of the chilled water loop
    #     to provide waterside economizing whenever wet bulb temperatures allow
    #   If 'non-integrated' will add a heat exchanger in parallel with the chiller that will operate
    #     only when it can meet cooling demand exclusively with the waterside economizing.
    # @param outdoor_air_reset [Boolean] whether to apply outdoor air temperature reset to the supply water temperature.
    #   Default is a false, using a constant setpoint supply water temperature.
    # @return [OpenStudio::Model::PlantLoop] the resulting chilled water loop
    def self.model_add_chw_loop(model,
                                system_name: 'Chilled Water Loop',
                                cooling_fuel: 'Electricity',
                                dsgn_sup_wtr_temp: 44.0,
                                dsgn_sup_wtr_temp_delt: 10.1,
                                chw_pumping_configuration: nil,
                                chiller_cooling_type: nil,
                                chiller_condenser_type: nil,
                                chiller_compressor_type: nil,
                                num_chillers: 1,
                                condenser_water_loop: nil,
                                waterside_economizer: 'none',
                                outdoor_air_reset: false)
      Composers.chw_loop(model,
                         system_name: system_name,
                         cooling_fuel: cooling_fuel,
                         dsgn_sup_wtr_temp: dsgn_sup_wtr_temp,
                         dsgn_sup_wtr_temp_delt: dsgn_sup_wtr_temp_delt,
                         chw_pumping_configuration: chw_pumping_configuration,
                         chiller_cooling_type: chiller_cooling_type,
                         chiller_condenser_type: chiller_condenser_type,
                         chiller_compressor_type: chiller_compressor_type,
                         num_chillers: num_chillers,
                         condenser_water_loop: condenser_water_loop,
                         waterside_economizer: waterside_economizer,
                         outdoor_air_reset: outdoor_air_reset)
    end

    # Creates a condenser water loop and adds it to the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param system_name [String] the name of the system, or nil in which case it will be defaulted
    # @param cooling_tower_type [String] valid choices are Open Cooling Tower, Closed Cooling Tower
    # @param cooling_tower_fan_type [String] valid choices are Centrifugal, "Propeller or Axial"
    # @param cooling_tower_capacity_control [String] valid choices are Fluid Bypass, Fan Cycling, TwoSpeed Fan, Variable Speed Fan
    # @param number_of_cells_per_tower [Integer] the number of discrete cells per tower
    # @param number_cooling_towers [Integer] the number of cooling towers to be added (in parallel)
    # @param use_90_1_design_sizing [Boolean] will determine the design sizing temperatures based on the 90.1 Appendix G approach.
    #   Overrides sup_wtr_temp, dsgn_sup_wtr_temp, dsgn_sup_wtr_temp_delt, and wet_bulb_approach if true.
    # @param sup_wtr_temp [Double] supply water temperature in degrees Fahrenheit, default 70F
    # @param dsgn_sup_wtr_temp [Double] design supply water temperature in degrees Fahrenheit, default 85F
    # @param dsgn_sup_wtr_temp_delt [Double] design water range temperature in degrees Rankine, default 10R
    # @param wet_bulb_approach [Double] design wet bulb approach temperature, default 7R
    # @param pump_spd_ctrl [String] pump speed control type, Constant or Variable (default)
    # @param pump_tot_hd [Double] pump head in ft H2O
    # @return [OpenStudio::Model::PlantLoop] the resulting condenser water plant loop
    def self.model_add_cw_loop(model,
                               system_name: 'Condenser Water Loop',
                               cooling_tower_type: 'Open Cooling Tower',
                               cooling_tower_fan_type: 'Propeller or Axial',
                               cooling_tower_capacity_control: 'TwoSpeed Fan',
                               number_of_cells_per_tower: 1,
                               number_cooling_towers: 1,
                               use_90_1_design_sizing: true,
                               sup_wtr_temp: 70.0,
                               dsgn_sup_wtr_temp: 85.0,
                               dsgn_sup_wtr_temp_delt: 10.0,
                               wet_bulb_approach: 7.0,
                               pump_spd_ctrl: 'Constant',
                               pump_tot_hd: 49.7)
      Composers.cw_loop(model,
                        system_name: system_name,
                        cooling_tower_type: cooling_tower_type,
                        cooling_tower_fan_type: cooling_tower_fan_type,
                        cooling_tower_capacity_control: cooling_tower_capacity_control,
                        number_of_cells_per_tower: number_of_cells_per_tower,
                        number_cooling_towers: number_cooling_towers,
                        use_90_1_design_sizing: use_90_1_design_sizing,
                        sup_wtr_temp: sup_wtr_temp,
                        dsgn_sup_wtr_temp: dsgn_sup_wtr_temp,
                        dsgn_sup_wtr_temp_delt: dsgn_sup_wtr_temp_delt,
                        wet_bulb_approach: wet_bulb_approach,
                        pump_spd_ctrl: pump_spd_ctrl,
                        pump_tot_hd: pump_tot_hd)
    end

    # Applies the 90.1-2010 G3.1.3.11 approach-temperature sizing methodology to a condenser
    # water loop that already exists in the model.
    #
    # This is model-state-dependent and therefore imperative: it reads the model's summer design
    # days (falling back to the weather file's .ddy, then to the CTI 78F rating condition) to find
    # the design wet bulb, then sizes the loop and its towers from it. It runs as a tail step after
    # the loop is built, so a declaratively composed loop and a legacy one size identically.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param condenser_water_loop [OpenStudio::Model::PlantLoop] the condenser water loop to size
    # @return [Boolean] returns true if successful, false if not
    def self.apply_90_1_condenser_water_sizing(model, condenser_water_loop)
      # use the formulation in 90.1-2010 G3.1.3.11 to set the approach temperature
      std = Standard.build('90.1-2010')
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.Prototype.hvac_systems', "Using the 90.1-2010 G3.1.3.11 approach temperature sizing methodology for condenser loop #{condenser_water_loop.name}.")

      # first, look in the model design day objects for sizing information
      summer_oat_wbs_f = []
      condenser_water_loop.model.getDesignDays.sort.each do |dd|
        next unless dd.dayType == 'SummerDesignDay'
        next unless dd.name.get.to_s.include?('WB=>MDB')

        if condenser_water_loop.model.version < OpenStudio::VersionString.new('3.3.0')
          if dd.humidityIndicatingType == 'Wetbulb'
            summer_oat_wb_c = dd.humidityIndicatingConditionsAtMaximumDryBulb
            summer_oat_wbs_f << OpenStudio.convert(summer_oat_wb_c, 'C', 'F').get
          else
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Prototype.hvac_systems', "For #{dd.name}, humidity is specified as #{dd.humidityIndicatingType}; cannot determine Twb.")
          end
        else
          if dd.humidityConditionType == 'Wetbulb' && dd.wetBulbOrDewPointAtMaximumDryBulb.is_initialized
            summer_oat_wbs_f << OpenStudio.convert(dd.wetBulbOrDewPointAtMaximumDryBulb.get, 'C', 'F').get
          else
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Prototype.hvac_systems', "For #{dd.name}, humidity is specified as #{dd.humidityConditionType}; cannot determine Twb.")
          end
        end
      end

      # if no design day objects are present in the model, attempt to load the .ddy file directly
      if summer_oat_wbs_f.empty?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Prototype.hvac_systems', 'No valid WB=>MDB Summer Design Days were found in the model.  Attempting to load wet bulb sizing from the .ddy file directly.')
        if model.weatherFile.is_initialized && model.weatherFile.get.path.is_initialized
          weather_file_path = model.weatherFile.get.path.get.to_s
          # Run differently depending on whether running from embedded filesystem in OpenStudio CLI or not
          if weather_file_path[0] == ':' # Running from OpenStudio CLI
            # Attempt to load in the ddy file based on convention that it is in the same directory and has the same basename as the epw file.
            ddy_file = weather_file_path.gsub('.epw', '.ddy')
            if EmbeddedScripting.hasFile(ddy_file)
              ddy_string = EmbeddedScripting.getFileAsString(ddy_file)
              temp_ddy_path = "#{Dir.pwd}/in.ddy"
              File.open(temp_ddy_path, 'wb') do |f|
                f << ddy_string
                f.flush
              end
              ddy_model = OpenStudio::EnergyPlus.loadAndTranslateIdf(temp_ddy_path).get
              FileUtils.rm_rf(temp_ddy_path)
            else
              OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Prototype.hvac_systems', "Could not locate a .ddy file for weather file path #{weather_file_path}")
            end
          else
            # Attempt to load in the ddy file based on convention that it is in the same directory and has the same basename as the epw file.
            ddy_file = "#{File.join(File.dirname(weather_file_path), File.basename(weather_file_path, '.*'))}.ddy"
            if File.exist? ddy_file
              ddy_model = OpenStudio::EnergyPlus.loadAndTranslateIdf(ddy_file).get
            else
              OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Prototype.hvac_systems', "Could not locate a .ddy file for weather file path #{weather_file_path}")
            end
          end

          unless ddy_model.nil?
            ddy_model.getDesignDays.sort.each do |dd|
              # Save the model wetbulb design conditions Condns WB=>MDB
              if dd.name.get.include? '4% Condns WB=>MDB'
                if model.version < OpenStudio::VersionString.new('3.3.0')
                  summer_oat_wb_c = dd.humidityIndicatingConditionsAtMaximumDryBulb
                  summer_oat_wbs_f << OpenStudio.convert(summer_oat_wb_c, 'C', 'F').get
                else
                  if dd.wetBulbOrDewPointAtMaximumDryBulb.is_initialized
                    summer_oat_wb_c = dd.wetBulbOrDewPointAtMaximumDryBulb.get
                    summer_oat_wbs_f << OpenStudio.convert(summer_oat_wb_c, 'C', 'F').get
                  end
                end
              end
            end
          end
        else
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Prototype.hvac_systems', 'The model does not have a weather file object or path specified in the object. Cannot get .ddy file directory.')
        end
      end

      # if values are still absent, use the CTI rating condition 78F
      design_oat_wb_f = nil
      if summer_oat_wbs_f.empty?
        design_oat_wb_f = 78.0
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Prototype.hvac_systems', "For condenser loop #{condenser_water_loop.name}, no design day OATwb conditions found.  CTI rating condition of 78F OATwb will be used for sizing cooling towers.")
      else
        # Take worst case condition
        design_oat_wb_f = summer_oat_wbs_f.max
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.Prototype.hvac_systems', "The maximum design wet bulb temperature from the Summer Design Day WB=>MDB is #{design_oat_wb_f} F")
      end
      design_oat_wb_c = OpenStudio.convert(design_oat_wb_f, 'F', 'C').get

      # call method to apply design sizing to the condenser water loop
      std.prototype_apply_condenser_water_temperatures(condenser_water_loop, design_wet_bulb_c: design_oat_wb_c)
    end

    # Creates a heat pump loop which has a boiler and fluid cooler for supplemental heating/cooling and adds it to the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param heating_fuel [String]
    # @param cooling_fuel [String] cooling fuel. Valid options are: Electricity, DistrictCooling
    # @param cooling_type [String] cooling type if not DistrictCooling.
    #   Valid options are:
    #   CoolingTower, CoolingTowerSingleSpeed, CoolingTowerTwoSpeed, CoolingTowerVariableSpeed,
    #   FluidCooler, FluidCoolerSingleSpeed, FluidCoolerTwoSpeed,
    #   EvaporativeFluidCooler, EvaporativeFluidCoolerSingleSpeed, EvaporativeFluidCoolerTwoSpeed
    # @param system_name [String] the name of the system, or nil in which case it will be defaulted
    # @param sup_wtr_high_temp [Double] target supply water temperature to enable cooling in degrees Fahrenheit, default 65.0F
    # @param sup_wtr_low_temp [Double] target supply water temperature to enable heating in degrees Fahrenheit, default 41.0F
    # @param dsgn_sup_wtr_temp [Double] design supply water temperature in degrees Fahrenheit, default 102.2F
    # @param dsgn_sup_wtr_temp_delt [Double] design supply-return water temperature difference in degrees Rankine, default 19.8R
    # @return [OpenStudio::Model::PlantLoop] the resulting plant loop
    # @todo replace cooling tower with fluid cooler after fixing sizing inputs
    def self.model_add_hp_loop(model,
                               heating_fuel: 'NaturalGas',
                               cooling_fuel: 'Electricity',
                               cooling_type: 'EvaporativeFluidCooler',
                               system_name: 'Heat Pump Loop',
                               sup_wtr_high_temp: 87.0,
                               sup_wtr_low_temp: 67.0,
                               dsgn_sup_wtr_temp: 102.2,
                               dsgn_sup_wtr_temp_delt: 19.8)
      Composers.hp_loop(model,
                        heating_fuel: heating_fuel,
                        cooling_fuel: cooling_fuel,
                        cooling_type: cooling_type,
                        system_name: system_name,
                        sup_wtr_high_temp: sup_wtr_high_temp,
                        sup_wtr_low_temp: sup_wtr_low_temp,
                        dsgn_sup_wtr_temp: dsgn_sup_wtr_temp,
                        dsgn_sup_wtr_temp_delt: dsgn_sup_wtr_temp_delt)
    end

    # Creates loop that roughly mimics a properly sized ground heat exchanger for supplemental heating/cooling and adds it to the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param system_name [String] the name of the system, or nil in which case it will be defaulted
    # @return [OpenStudio::Model::PlantLoop] the resulting plant loop
    # @todo replace condenser loop w/ ground HX model that does not involve district objects
    def self.model_add_ground_hx_loop(model,
                                      system_name: 'Ground HX Loop')
      Composers.ground_hx_loop(model, system_name: system_name)
    end

    # Adds an ambient condenser water loop that will be used in a district to connect buildings as a shared sink/source for heat pumps.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param system_name [String] the name of the system, or nil in which case it will be defaulted
    # @return [OpenStudio::Model::PlantLoop] the ambient loop
    # @todo add inputs for design temperatures like heat pump loop object
    # @todo handle ground and heat pump with this; make heating/cooling source options (boiler, fluid cooler, district)
    def self.model_add_district_ambient_loop(model,
                                             system_name: 'Ambient Loop')
      Composers.district_ambient_loop(model, system_name: system_name)
    end

    # Model a 2-pipe plant loop, where the loop is either in heating or cooling.
    # For sizing reasons, this method keeps separate hot water and chilled water loops,
    # and connects them together with a common inverse schedule.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param hot_water_loop [OpenStudio::Model::PlantLoop] the hot water loop
    # @param chilled_water_loop [OpenStudio::Model::PlantLoop] the chilled water loop
    # @param control_strategy [String] Method to determine whether the loop is in heating or cooling mode
    #   'outdoor_air_lockout' - The system will be in heating below the lockout_temperature variable,
    #      and cooling above the lockout_temperature. Requires the lockout_temperature variable.
    #   'zone_demand' - Heating or cooling determined by preponderance of zone demand.
    #      Requires thermal_zones defined.
    # @param lockout_temperature [Double] lockout temperature in degrees Fahrenheit, default 65F.
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones
    # @return [OpenStudio::Model::ScheduleRuleset]
    def self.model_two_pipe_loop(model,
                                 hot_water_loop,
                                 chilled_water_loop,
                                 control_strategy: 'outdoor_air_lockout',
                                 lockout_temperature: 65.0,
                                 thermal_zones: [])
      if control_strategy == 'outdoor_air_lockout'
        # get or create outdoor sensor node to be used in plant availability managers if needed
        outdoor_airnode = model.outdoorAirNode

        # create availability managers based on outdoor temperature
        # create hot water plant availability manager
        hot_water_loop_lockout_manager = OpenStudio::Model::AvailabilityManagerHighTemperatureTurnOff.new(model)
        hot_water_loop_lockout_manager.setName("#{hot_water_loop.name} Lockout Manager")
        hot_water_loop_lockout_manager.setSensorNode(outdoor_airnode)
        hot_water_loop_lockout_manager.setTemperature(OpenStudio.convert(lockout_temperature, 'F', 'C').get)

        # set availability manager to hot water plant
        hot_water_loop.addAvailabilityManager(hot_water_loop_lockout_manager)

        # create chilled water plant availability manager
        chilled_water_loop_lockout_manager = OpenStudio::Model::AvailabilityManagerLowTemperatureTurnOff.new(model)
        chilled_water_loop_lockout_manager.setName("#{chilled_water_loop.name} Lockout Manager")
        chilled_water_loop_lockout_manager.setSensorNode(outdoor_airnode)
        chilled_water_loop_lockout_manager.setTemperature(OpenStudio.convert(lockout_temperature, 'F', 'C').get)

        # set availability manager to hot water plant
        chilled_water_loop.addAvailabilityManager(chilled_water_loop_lockout_manager)
      else
        # create availability managers based on zone heating and cooling demand
        hot_water_loop_name = OpenstudioStandards::HVAC.ems_friendly_name(hot_water_loop.name)
        chilled_water_loop_name = OpenstudioStandards::HVAC.ems_friendly_name(chilled_water_loop.name)

        # create hot water plant availability schedule managers and create an EMS acuator
        sch_hot_water_availability = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                                     0,
                                                                                                     name: "#{hot_water_loop.name} Availability Schedule",
                                                                                                     schedule_type_limit: 'OnOff')

        hot_water_loop_manager = OpenStudio::Model::AvailabilityManagerScheduled.new(model)
        hot_water_loop_manager.setName("#{hot_water_loop.name} Availability Manager")
        hot_water_loop_manager.setSchedule(sch_hot_water_availability)

        hot_water_plant_ctrl = OpenStudio::Model::EnergyManagementSystemActuator.new(sch_hot_water_availability,
                                                                                     'Schedule:Year',
                                                                                     'Schedule Value')
        hot_water_plant_ctrl.setName("#{hot_water_loop_name}_availability_control")

        # set availability manager to hot water plant
        hot_water_loop.addAvailabilityManager(hot_water_loop_manager)

        # create chilled water plant availability schedule managers and create an EMS acuator
        sch_chilled_water_availability = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                                         0,
                                                                                                         name: "#{chilled_water_loop.name} Availability Schedule",
                                                                                                         schedule_type_limit: 'OnOff')

        chilled_water_loop_manager = OpenStudio::Model::AvailabilityManagerScheduled.new(model)
        chilled_water_loop_manager.setName("#{chilled_water_loop.name} Availability Manager")
        chilled_water_loop_manager.setSchedule(sch_chilled_water_availability)

        chilled_water_plant_ctrl = OpenStudio::Model::EnergyManagementSystemActuator.new(sch_chilled_water_availability,
                                                                                         'Schedule:Year',
                                                                                         'Schedule Value')
        chilled_water_plant_ctrl.setName("#{chilled_water_loop_name}_availability_control")

        # set availability manager to chilled water plant
        chilled_water_loop.addAvailabilityManager(chilled_water_loop_manager)

        # check if zone heat and cool requests program exists, if not create it
        determine_zone_cooling_needs_prg = model.getEnergyManagementSystemProgramByName('Determine_Zone_Cooling_Needs')
        determine_zone_heating_needs_prg = model.getEnergyManagementSystemProgramByName('Determine_Zone_Heating_Needs')
        unless determine_zone_cooling_needs_prg.is_initialized && determine_zone_heating_needs_prg.is_initialized
          OpenstudioStandards::HVAC.model_add_zone_heat_cool_request_count_program(model, thermal_zones)
        end

        # create program to determine plant heating or cooling mode
        determine_plant_mode_prg = OpenStudio::Model::EnergyManagementSystemProgram.new(model)
        determine_plant_mode_prg.setName('Determine_Heating_Cooling_Plant_Mode')
        determine_plant_mode_prg_body = <<-EMS
        IF Zone_Heating_Ratio > 0.5,
          SET #{hot_water_loop_name}_availability_control = 1,
          SET #{chilled_water_loop_name}_availability_control = 0,
        ELSEIF Zone_Cooling_Ratio > 0.5,
          SET #{hot_water_loop_name}_availability_control = 0,
          SET #{chilled_water_loop_name}_availability_control = 1,
        ELSE,
          SET #{hot_water_loop_name}_availability_control = #{hot_water_loop_name}_availability_control,
          SET #{chilled_water_loop_name}_availability_control = #{chilled_water_loop_name}_availability_control,
        ENDIF
        EMS
        determine_plant_mode_prg.setBody(determine_plant_mode_prg_body)

        # create EMS program manager objects
        programs_at_beginning_of_timestep = OpenStudio::Model::EnergyManagementSystemProgramCallingManager.new(model)
        programs_at_beginning_of_timestep.setName('Heating_Cooling_Demand_Based_Plant_Availability_At_Beginning_Of_Timestep')
        programs_at_beginning_of_timestep.setCallingPoint('BeginTimestepBeforePredictor')
        programs_at_beginning_of_timestep.addProgram(determine_plant_mode_prg)
      end
    end

    # Creates a DOAS system with cold supply and terminal units for each zone.
    # This is the default DOAS system for DOE prototype buildings. Use model_add_doas for other DOAS systems.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to connect to this system
    # @param system_name [String] the name of the system, or nil in which case it will be defaulted
    # @param hot_water_loop [OpenStudio::Model::PlantLoop] hot water loop to connect to heating and zone fan coils
    # @param chilled_water_loop [OpenStudio::Model::PlantLoop] chilled water loop to connect to cooling coil
    # @param hvac_op_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the HVAC Operating Schedule. Defaults to always on if nil.
    # @param min_oa_sch [OpenStudio::Model::Schedule]  OpenStudio Schedule object for the minimum outdoor air schedule. Defaults to always on if nil.
    # @param min_frac_oa_sch [String] OpenStudio Schedule object for the minimum fraction of outdoor air schedule. Defaults to always on if nil.
    # @param fan_maximum_flow_rate [Double] fan maximum flow rate in cfm, default is autosize
    # @param econo_ctrl_mthd [String] economizer control type, default is Fixed Dry Bulb
    # @param energy_recovery [Boolean] if true, an ERV will be added to the system
    # @param doas_control_strategy [String] DOAS control strategy
    # @param clg_dsgn_sup_air_temp [Double] design cooling supply air temperature in degrees Fahrenheit, default 65F
    # @param htg_dsgn_sup_air_temp [Double] design heating supply air temperature in degrees Fahrenheit, default 75F
    # @return [OpenStudio::Model::AirLoopHVAC] the resulting DOAS air loop
    def self.model_add_doas_cold_supply(model,
                                        thermal_zones,
                                        system_name: nil,
                                        hot_water_loop: nil,
                                        chilled_water_loop: nil,
                                        hvac_op_sch: nil,
                                        min_oa_sch: nil,
                                        min_frac_oa_sch: nil,
                                        fan_maximum_flow_rate: nil,
                                        econo_ctrl_mthd: 'FixedDryBulb',
                                        energy_recovery: false,
                                        doas_control_strategy: 'NeutralSupplyAir',
                                        clg_dsgn_sup_air_temp: 55.0,
                                        htg_dsgn_sup_air_temp: 60.0)
      Composers.doas_cold_supply(model,
                                 thermal_zones,
                                 system_name: system_name,
                                 hot_water_loop: hot_water_loop,
                                 chilled_water_loop: chilled_water_loop,
                                 hvac_op_sch: hvac_op_sch,
                                 min_oa_sch: min_oa_sch,
                                 min_frac_oa_sch: min_frac_oa_sch,
                                 fan_maximum_flow_rate: fan_maximum_flow_rate,
                                 econo_ctrl_mthd: econo_ctrl_mthd,
                                 energy_recovery: energy_recovery,
                                 doas_control_strategy: doas_control_strategy,
                                 clg_dsgn_sup_air_temp: clg_dsgn_sup_air_temp,
                                 htg_dsgn_sup_air_temp: htg_dsgn_sup_air_temp)
    end

    # Creates a DOAS system with terminal units for each zone.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to connect to this system
    # @param system_name [String] the name of the system, or nil in which case it will be defaulted
    # @param doas_type [String] DOASCV or DOASVAV, determines whether the DOAS is operated at scheduled,
    #   constant flow rate, or airflow is variable to allow for economizing or demand controlled ventilation
    # @param doas_control_strategy [String] DOAS control strategy
    # @param hot_water_loop [OpenStudio::Model::PlantLoop] hot water loop to connect to heating and zone fan coils
    # @param chilled_water_loop [OpenStudio::Model::PlantLoop] chilled water loop to connect to cooling coil
    # @param hvac_op_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the HVAC Operating Schedule. Defaults to always on if nil.
    # @param min_oa_sch [OpenStudio::Model::Schedule]  OpenStudio Schedule object for the minimum outdoor air schedule. Defaults to always on if nil.
    # @param min_frac_oa_sch [String] OpenStudio Schedule object for the minimum fraction of outdoor air schedule. Defaults to always on if nil.
    # @param fan_maximum_flow_rate [Double] fan maximum flow rate in cfm, default is autosize
    # @param econo_ctrl_mthd [String] economizer control type, default is Fixed Dry Bulb
    #   If enabled, the DOAS will be sized for twice the ventilation minimum to allow economizing
    # @param include_exhaust_fan [Boolean] if true, include an exhaust fan
    # @param clg_dsgn_sup_air_temp [Double] design cooling supply air temperature in degrees Fahrenheit, default 65F
    # @param htg_dsgn_sup_air_temp [Double] design heating supply air temperature in degrees Fahrenheit, default 75F
    # @return [OpenStudio::Model::AirLoopHVAC] the resulting DOAS air loop
    def self.model_add_doas(model,
                            thermal_zones,
                            system_name: nil,
                            doas_type: 'DOASCV',
                            hot_water_loop: nil,
                            chilled_water_loop: nil,
                            hvac_op_sch: nil,
                            min_oa_sch: nil,
                            min_frac_oa_sch: nil,
                            fan_maximum_flow_rate: nil,
                            econo_ctrl_mthd: 'NoEconomizer',
                            include_exhaust_fan: true,
                            demand_control_ventilation: false,
                            doas_control_strategy: 'NeutralSupplyAir',
                            clg_dsgn_sup_air_temp: 60.0,
                            htg_dsgn_sup_air_temp: 70.0)
      Composers.doas(model,
                     thermal_zones,
                     system_name: system_name,
                     doas_type: doas_type,
                     hot_water_loop: hot_water_loop,
                     chilled_water_loop: chilled_water_loop,
                     hvac_op_sch: hvac_op_sch,
                     min_oa_sch: min_oa_sch,
                     min_frac_oa_sch: min_frac_oa_sch,
                     fan_maximum_flow_rate: fan_maximum_flow_rate,
                     econo_ctrl_mthd: econo_ctrl_mthd,
                     include_exhaust_fan: include_exhaust_fan,
                     demand_control_ventilation: demand_control_ventilation,
                     doas_control_strategy: doas_control_strategy,
                     clg_dsgn_sup_air_temp: clg_dsgn_sup_air_temp,
                     htg_dsgn_sup_air_temp: htg_dsgn_sup_air_temp)
    end

    # Creates a VAV system and adds it to the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to connect to this system
    # @param system_name [String] the name of the system, or nil in which case it will be defaulted
    # @param return_plenum [OpenStudio::Model::ThermalZone] the zone to attach as the supply plenum, or nil, in which case no return plenum will be used
    # @param heating_type [String] main heating coil fuel type
    #   valid choices are NaturalGas, Gas, Electricity, HeatPump, DistrictHeating, DistrictHeatingWater, DistrictHeatingSteam, or nil (defaults to NaturalGas)
    # @param reheat_type [String] valid options are NaturalGas, Gas, Electricity, Water, nil (no heat)
    # @param hot_water_loop [OpenStudio::Model::PlantLoop] hot water loop to connect heating and reheat coils to
    # @param chilled_water_loop [OpenStudio::Model::PlantLoop] chilled water loop to connect cooling coil to
    # @param hvac_op_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the HVAC Operating Schedule. Defaults to always on if nil.
    # @param oa_damper_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the OA damper schedule. Defaults to always on if nil.
    # @param fan_efficiency [Double] fan total efficiency, including motor and impeller
    # @param fan_motor_efficiency [Double] fan motor efficiency
    # @param fan_pressure_rise [Double] fan pressure rise, inH2O
    # @param min_sys_airflow_ratio [Double, Symbol] central heating maximum system air flow ratio, the
    #   fraction of the cooling design flow the central heating coil is sized to heat. Defaults to
    #   :autosize, which lets EnergyPlus derive it from the zones' heating design flows - the airflow
    #   the terminals pass in heating once minimum outdoor air is counted. Pass a number to pin it;
    #   the DOE prototypes pin 0.3. See set_air_loop_system_sizing.
    # @param vav_sizing_option [String] air system sizing option, Coincident or NonCoincident
    # @param econo_ctrl_mthd [String] economizer control type
    # @return [OpenStudio::Model::AirLoopHVAC] the resulting VAV air loop
    def self.model_add_vav_reheat(model,
                                  thermal_zones,
                                  system_name: nil,
                                  return_plenum: nil,
                                  heating_type: nil,
                                  reheat_type: nil,
                                  hot_water_loop: nil,
                                  chilled_water_loop: nil,
                                  hvac_op_sch: nil,
                                  oa_damper_sch: nil,
                                  fan_efficiency: 0.62,
                                  fan_motor_efficiency: 0.9,
                                  fan_pressure_rise: 4.0,
                                  min_sys_airflow_ratio: :autosize,
                                  vav_sizing_option: 'Coincident',
                                  econo_ctrl_mthd: nil)
      Composers.vav_reheat(model,
                           thermal_zones,
                           system_name: system_name,
                           return_plenum: return_plenum,
                           heating_type: heating_type,
                           reheat_type: reheat_type,
                           hot_water_loop: hot_water_loop,
                           chilled_water_loop: chilled_water_loop,
                           hvac_op_sch: hvac_op_sch,
                           oa_damper_sch: oa_damper_sch,
                           fan_efficiency: fan_efficiency,
                           fan_motor_efficiency: fan_motor_efficiency,
                           fan_pressure_rise: fan_pressure_rise,
                           min_sys_airflow_ratio: min_sys_airflow_ratio,
                           vav_sizing_option: vav_sizing_option,
                           econo_ctrl_mthd: econo_ctrl_mthd)
    end

    # Creates a VAV system with parallel fan powered boxes and adds it to the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to connect to this system
    # @param system_name [String] the name of the system, or nil in which case it will be defaulted
    # @param chilled_water_loop [OpenStudio::Model::PlantLoop] chilled water loop to connect to the cooling coil
    # @param hvac_op_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the HVAC Operating Schedule. Defaults to always on if nil.
    # @param oa_damper_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the OA damper schedule. Defaults to always on if nil.
    # @param fan_efficiency [Double] fan total efficiency, including motor and impeller
    # @param fan_motor_efficiency [Double] fan motor efficiency
    # @param fan_pressure_rise [Double] fan pressure rise, inH2O
    # @param min_sys_airflow_ratio [Double, Symbol] central heating maximum system air flow ratio;
    #   :autosize (the default) or a number to pin it. See model_add_vav_reheat.
    # @return [OpenStudio::Model::AirLoopHVAC] the resulting VAV air loop
    def self.model_add_vav_pfp_boxes(model,
                                     thermal_zones,
                                     system_name: nil,
                                     chilled_water_loop: nil,
                                     hvac_op_sch: nil,
                                     oa_damper_sch: nil,
                                     fan_efficiency: 0.62,
                                     fan_motor_efficiency: 0.9,
                                     fan_pressure_rise: 4.0,
                                     min_sys_airflow_ratio: :autosize)
      Composers.vav_pfp_boxes(model,
                              thermal_zones,
                              system_name: system_name,
                              chilled_water_loop: chilled_water_loop,
                              hvac_op_sch: hvac_op_sch,
                              oa_damper_sch: oa_damper_sch,
                              fan_efficiency: fan_efficiency,
                              fan_motor_efficiency: fan_motor_efficiency,
                              fan_pressure_rise: fan_pressure_rise,
                              min_sys_airflow_ratio: min_sys_airflow_ratio)
    end

    # Creates a packaged VAV system and adds it to the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to connect to this system
    # @param system_name [String] the name of the system, or nil in which case it will be defaulted
    # @param return_plenum [OpenStudio::Model::ThermalZone] the zone to attach as the supply plenum, or nil, in which case no return plenum will be used
    # @param hot_water_loop [OpenStudio::Model::PlantLoop] hot water loop to connect heating and reheat coils to. If nil, will be electric heat and electric reheat
    # @param chilled_water_loop [OpenStudio::Model::PlantLoop] chilled water loop to connect cooling coils to. If nil, will be DX cooling
    # @param heating_type [String] main heating coil fuel type
    #   valid choices are NaturalGas, Electricity, Water, or nil (defaults to NaturalGas)
    # @param electric_reheat [Boolean] if true electric reheat coils, if false the reheat coils served by hot_water_loop
    # @param hvac_op_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the HVAC Operating Schedule. Defaults to always on if nil.
    # @param oa_damper_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the OA damper schedule. Defaults to always on if nil.
    # @param econo_ctrl_mthd [String] economizer control type
    # @param min_sys_airflow_ratio [Double, Symbol] central heating maximum system air flow ratio;
    #   :autosize (the default) or a number to pin it. See model_add_vav_reheat.
    # @return [OpenStudio::Model::AirLoopHVAC] the resulting packaged VAV air loop
    def self.model_add_pvav(model,
                            thermal_zones,
                            system_name: nil,
                            return_plenum: nil,
                            hot_water_loop: nil,
                            chilled_water_loop: nil,
                            heating_type: nil,
                            electric_reheat: false,
                            hvac_op_sch: nil,
                            oa_damper_sch: nil,
                            econo_ctrl_mthd: nil,
                            min_sys_airflow_ratio: :autosize)
      Composers.pvav(model,
                     thermal_zones,
                     system_name: system_name,
                     return_plenum: return_plenum,
                     hot_water_loop: hot_water_loop,
                     chilled_water_loop: chilled_water_loop,
                     heating_type: heating_type,
                     electric_reheat: electric_reheat,
                     hvac_op_sch: hvac_op_sch,
                     oa_damper_sch: oa_damper_sch,
                     econo_ctrl_mthd: econo_ctrl_mthd,
                     min_sys_airflow_ratio: min_sys_airflow_ratio)
    end

    # Creates a packaged VAV system with parallel fan powered boxes and adds it to the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to connect to this system
    # @param system_name [String] the name of the system, or nil in which case it will be defaulted
    # @param chilled_water_loop [OpenStudio::Model::PlantLoop] chilled water loop to connect cooling coils to. If nil, will be DX cooling
    # @param hvac_op_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the HVAC Operating Schedule. Defaults to always on if nil.
    # @param oa_damper_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the OA damper schedule. Defaults to always on if nil.
    # @param fan_efficiency [Double] fan total efficiency, including motor and impeller
    # @param fan_motor_efficiency [Double] fan motor efficiency
    # @param fan_pressure_rise [Double] fan pressure rise, inH2O
    # @param min_sys_airflow_ratio [Double, Symbol] central heating maximum system air flow ratio;
    #   :autosize (the default) or a number to pin it. See model_add_vav_reheat.
    # @return [OpenStudio::Model::AirLoopHVAC] the resulting VAV air loop
    def self.model_add_pvav_pfp_boxes(model,
                                      thermal_zones,
                                      system_name: nil,
                                      chilled_water_loop: nil,
                                      hvac_op_sch: nil,
                                      oa_damper_sch: nil,
                                      fan_efficiency: 0.62,
                                      fan_motor_efficiency: 0.9,
                                      fan_pressure_rise: 4.0,
                                      min_sys_airflow_ratio: :autosize)
      Composers.pvav_pfp_boxes(model,
                               thermal_zones,
                               system_name: system_name,
                               chilled_water_loop: chilled_water_loop,
                               hvac_op_sch: hvac_op_sch,
                               oa_damper_sch: oa_damper_sch,
                               fan_efficiency: fan_efficiency,
                               fan_motor_efficiency: fan_motor_efficiency,
                               fan_pressure_rise: fan_pressure_rise,
                               min_sys_airflow_ratio: min_sys_airflow_ratio)
    end

    # Creates a CAV system and adds it to the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to connect to this system
    # @param system_name [String] the name of the system, or nil in which case it will be defaulted
    # @param hot_water_loop [OpenStudio::Model::PlantLoop] hot water loop to connect to heating and reheat coils.
    # @param chilled_water_loop [OpenStudio::Model::PlantLoop] chilled water loop to connect to the cooling coil.
    # @param hvac_op_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the HVAC Operating Schedule. Defaults to always on if nil.
    # @param oa_damper_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the OA damper schedule. Defaults to always on if nil.
    # @param fan_efficiency [Double] fan total efficiency, including motor and impeller
    # @param fan_motor_efficiency [Double] fan motor efficiency
    # @param fan_pressure_rise [Double] fan pressure rise, inH2O
    # @return [OpenStudio::Model::AirLoopHVAC] the resulting packaged VAV air loop
    def self.model_add_cav(model,
                           thermal_zones,
                           system_name: nil,
                           hot_water_loop: nil,
                           chilled_water_loop: nil,
                           hvac_op_sch: nil,
                           oa_damper_sch: nil,
                           fan_efficiency: 0.62,
                           fan_motor_efficiency: 0.9,
                           fan_pressure_rise: 4.0)
      Composers.cav(model,
                    thermal_zones,
                    system_name: system_name,
                    hot_water_loop: hot_water_loop,
                    chilled_water_loop: chilled_water_loop,
                    hvac_op_sch: hvac_op_sch,
                    oa_damper_sch: oa_damper_sch,
                    fan_efficiency: fan_efficiency,
                    fan_motor_efficiency: fan_motor_efficiency,
                    fan_pressure_rise: fan_pressure_rise)
    end

    # Creates a PSZ-AC system for each zone and adds it to the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to connect to this system
    # @param system_name [String] the name of the system, or nil in which case it will be defaulted
    # @param cooling_type [String] valid choices are Water, Two Speed DX AC, Single Speed DX AC, Single Speed Heat Pump, Water To Air Heat Pump
    # @param chilled_water_loop [OpenStudio::Model::PlantLoop] chilled water loop to connect cooling coil to, or nil
    # @param hot_water_loop [OpenStudio::Model::PlantLoop] hot water loop to connect heating coil to, or nil
    # @param heating_type [String] valid choices are NaturalGas, Electricity, Water, Single Speed Heat Pump, Water To Air Heat Pump, or nil (no heat)
    # @param supplemental_heating_type [String] valid choices are Electricity, NaturalGas,  nil (no heat)
    # @param fan_location [String] valid choices are BlowThrough, DrawThrough
    # @param fan_type [String] valid choices are ConstantVolume, Cycling
    # @param hvac_op_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the HVAC Operating Schedule. Defaults to always on if nil.
    # @param oa_damper_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the OA damper schedule. Defaults to always on if nil.
    # @param econ_max_oa_frac_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the economizer maximum outdoor air fraction schedule.
    # @return [Array<OpenStudio::Model::AirLoopHVAC>] an array of the resulting PSZ-AC air loops
    def self.model_add_psz_ac(model,
                              thermal_zones,
                              system_name: nil,
                              cooling_type: 'Single Speed DX AC',
                              chilled_water_loop: nil,
                              hot_water_loop: nil,
                              heating_type: nil,
                              supplemental_heating_type: nil,
                              fan_location: 'DrawThrough',
                              fan_type: 'ConstantVolume',
                              hvac_op_sch: nil,
                              oa_damper_sch: nil,
                              econ_max_oa_frac_sch: nil)
      Composers.psz_ac(model,
                       thermal_zones,
                       system_name: system_name,
                       cooling_type: cooling_type,
                       chilled_water_loop: chilled_water_loop,
                       hot_water_loop: hot_water_loop,
                       heating_type: heating_type,
                       supplemental_heating_type: supplemental_heating_type,
                       fan_location: fan_location,
                       fan_type: fan_type,
                       hvac_op_sch: hvac_op_sch,
                       oa_damper_sch: oa_damper_sch,
                       econ_max_oa_frac_sch: econ_max_oa_frac_sch)
    end

    # Creates a packaged single zone VAV system for each zone and adds it to the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to connect to this system
    # @param system_name [String] the name of the system, or nil in which case it will be defaulted
    # @param heating_type [String] valid choices are NaturalGas, Electricity, Water, nil (no heat)
    # @param supplemental_heating_type [String] valid choices are Electricity, NaturalGas,  nil (no heat)
    # @param hvac_op_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the HVAC Operating Schedule. Defaults to always on if nil.
    # @param oa_damper_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the OA damper schedule. Defaults to always on if nil.
    # @param econ_max_oa_frac_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the economizer maximum outdoor air fraction schedule.
    # @return [Array<OpenStudio::Model::AirLoopHVAC>] an array of the resulting PSZ-AC air loops
    def self.model_add_psz_vav(model,
                               thermal_zones,
                               system_name: nil,
                               heating_type: nil,
                               cooling_type: 'AirCooled',
                               supplemental_heating_type: nil,
                               hvac_op_sch: nil,
                               fan_type: 'VAV_System_Fan',
                               oa_damper_sch: nil,
                               econ_max_oa_frac_sch: nil,
                               hot_water_loop: nil,
                               chilled_water_loop: nil,
                               minimum_volume_setpoint: nil)
      Composers.psz_vav(model,
                        thermal_zones,
                        system_name: system_name,
                        heating_type: heating_type,
                        cooling_type: cooling_type,
                        supplemental_heating_type: supplemental_heating_type,
                        hvac_op_sch: hvac_op_sch,
                        fan_type: fan_type,
                        oa_damper_sch: oa_damper_sch,
                        econ_max_oa_frac_sch: econ_max_oa_frac_sch,
                        hot_water_loop: hot_water_loop,
                        chilled_water_loop: chilled_water_loop,
                        minimum_volume_setpoint: minimum_volume_setpoint)
    end

    # Adds a data center load to a given space.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param space [OpenStudio::Model::Space] which space to assign the data center loads to
    # @param dc_watts_per_area [Double] data center load, in W/m^2
    # @return [Boolean] returns true if successful, false if not
    def self.model_add_data_center_load(model, space, dc_watts_per_area)
      # create data center load
      data_center_definition = OpenStudio::Model::ElectricEquipmentDefinition.new(model)
      data_center_definition.setName('Data Center Load')
      data_center_definition.setWattsperSpaceFloorArea(dc_watts_per_area)
      data_center_equipment = OpenStudio::Model::ElectricEquipment.new(data_center_definition)
      data_center_equipment.setName('Data Center Load')
      data_center_sch = model.alwaysOnDiscreteSchedule
      data_center_equipment.setSchedule(data_center_sch)
      data_center_equipment.setSpace(space)

      return true
    end

    # Creates a data center PSZ-AC system for each zone.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param system_name [String] the name of the system, or nil in which case it will be defaulted
    # @param hot_water_loop [OpenStudio::Model::PlantLoop] hot water loop to connect to the heating coil
    # @param heat_pump_loop [OpenStudio::Model::PlantLoop] heat pump water loop to connect to heat pump
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to connect to this system
    # @param hvac_op_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the HVAC Operating Schedule. Defaults to always on if nil.
    # @param oa_damper_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the OA damper schedule. Defaults to always on if nil.
    # @param rel_hum_setp_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the relative humidity setpoint schedule. Defaults to 30% if nil.
    # @param main_data_center [Boolean] whether or not this is the main data center in the building.
    # @return [Array<OpenStudio::Model::AirLoopHVAC>] an array of the resulting air loops
    def self.model_add_data_center_hvac(model,
                                        thermal_zones,
                                        hot_water_loop,
                                        heat_pump_loop,
                                        system_name: nil,
                                        hvac_op_sch: nil,
                                        oa_damper_sch: nil,
                                        rel_hum_setp_sch: nil,
                                        main_data_center: false)
      Composers.data_center_hvac(model,
                                 thermal_zones,
                                 hot_water_loop,
                                 heat_pump_loop,
                                 system_name: system_name,
                                 hvac_op_sch: hvac_op_sch,
                                 oa_damper_sch: oa_damper_sch,
                                 rel_hum_setp_sch: rel_hum_setp_sch,
                                 main_data_center: main_data_center)
    end

    # Creates a CRAC system for data center and adds it to the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param system_name [String] the name of the system, or nil in which case it will be defaulted
    # @param thermal_zones [String] zones to connect to this system
    # @param hvac_op_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the HVAC Operating Schedule. Defaults to always on if nil.
    # @param oa_damper_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the OA damper schedule. Defaults to always on if nil.
    # @param rel_hum_setp_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the relative humidity setpoint schedule. Defaults to 8% if nil.
    # @param fan_location [Double] valid choices are BlowThrough, DrawThrough
    # @param fan_type [Double] valid choices are ConstantVolume, Cycling, VariableVolume
    # no heating
    # @param cooling_type [String] valid choices are Two Speed DX AC, Single Speed DX AC
    # @return [Array<OpenStudio::Model::AirLoopHVAC>] an array of the resulting CRAC air loops
    def self.model_add_crac(model,
                            thermal_zones,
                            climate_zone,
                            system_name: nil,
                            hvac_op_sch: nil,
                            oa_damper_sch: nil,
                            fan_location: 'DrawThrough',
                            fan_type: 'ConstantVolume',
                            cooling_type: 'Single Speed DX AC',
                            supply_temp_sch: nil,
                            rel_hum_setp_sch: nil)
      Composers.crac(model,
                     thermal_zones,
                     climate_zone,
                     system_name: system_name,
                     hvac_op_sch: hvac_op_sch,
                     oa_damper_sch: oa_damper_sch,
                     fan_location: fan_location,
                     fan_type: fan_type,
                     cooling_type: cooling_type,
                     supply_temp_sch: supply_temp_sch,
                     rel_hum_setp_sch: rel_hum_setp_sch)
    end

    # Creates a CRAH system for larger size data center and adds it to the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param chilled_water_loop [String
    # @param system_name [String] the name of the system, or nil in which case it will be defaulted
    # @param thermal_zones [String] zones to connect to this system
    # @param hvac_op_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the HVAC Operating Schedule. Defaults to always on if nil.
    # @param oa_damper_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the OA damper schedule. Defaults to always on if nil.
    # @param rel_hum_setp_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the relative humidity setpoint schedule. Defaults to 8% if nil.
    # no heating
    # @return [Array<OpenStudio::Model::AirLoopHVAC>] an array of the resulting CRAH air loops
    def self.model_add_crah(model,
                            thermal_zones,
                            system_name: nil,
                            chilled_water_loop: nil,
                            hvac_op_sch: nil,
                            oa_damper_sch: nil,
                            return_plenum: nil,
                            supply_temp_sch: nil,
                            rel_hum_setp_sch: nil)
      Composers.crah(model,
                     thermal_zones,
                     system_name: system_name,
                     chilled_water_loop: chilled_water_loop,
                     hvac_op_sch: hvac_op_sch,
                     oa_damper_sch: oa_damper_sch,
                     return_plenum: return_plenum,
                     supply_temp_sch: supply_temp_sch,
                     rel_hum_setp_sch: rel_hum_setp_sch)
    end

    # Creates a split DX AC system for each zone and adds it to the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to connect to this system
    # @param cooling_type [String] valid choices are Two Speed DX AC, Single Speed DX AC, Single Speed Heat Pump
    # @param heating_type [String] valid choices are Gas, Single Speed Heat Pump
    # @param supplemental_heating_type [String] valid choices are Electric, Gas
    # @param fan_type [String] valid choices are ConstantVolume, Cycling
    # @param hvac_op_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the HVAC Operating Schedule. Defaults to always on if nil.
    # @param oa_damper_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the OA damper schedule. Defaults to always on if nil.
    # @param econ_max_oa_frac_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the economizer maximum outdoor air fraction schedule.
    # @return [OpenStudio::Model::AirLoopHVAC] the resulting split AC air loop
    def self.model_add_split_ac(model,
                                thermal_zones,
                                cooling_type: 'Two Speed DX AC',
                                heating_type: 'Single Speed Heat Pump',
                                supplemental_heating_type: 'Gas',
                                fan_type: 'Cycling',
                                hvac_op_sch: nil,
                                oa_damper_sch: nil,
                                econ_max_oa_frac_sch: nil)
      Composers.split_ac(model,
                         thermal_zones,
                         cooling_type: cooling_type,
                         heating_type: heating_type,
                         supplemental_heating_type: supplemental_heating_type,
                         fan_type: fan_type,
                         hvac_op_sch: hvac_op_sch,
                         oa_damper_sch: oa_damper_sch,
                         econ_max_oa_frac_sch: econ_max_oa_frac_sch)
    end

    # Creates a minisplit heatpump system for each zone and adds it to the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to connect to this system
    # @param cooling_type [String] valid choices are Two Speed DX AC, Single Speed DX AC, Single Speed Heat Pump
    # @param heating_type [String] valid choices are Single Speed DX
    # @param hvac_op_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the HVAC Operating Schedule. Defaults to always on if nil.
    # @return [OpenStudio::Model::AirLoopHVAC] the resulting split AC air loop
    def self.model_add_minisplit_hp(model,
                                    thermal_zones,
                                    cooling_type: 'Two Speed DX AC',
                                    heating_type: 'Single Speed DX',
                                    hvac_op_sch: nil)
      Composers.minisplit_hp(model,
                             thermal_zones,
                             cooling_type: cooling_type,
                             heating_type: heating_type,
                             hvac_op_sch: hvac_op_sch)
    end

    # Creates a PTAC system for each zone and adds it to the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to connect to this system
    # @param cooling_type [String] valid choices are Two Speed DX AC, Single Speed DX AC
    # @param heating_type [String] valid choices are NaturalGas, Electricity, Water, nil (no heat)
    # @param hot_water_loop [OpenStudio::Model::PlantLoop] hot water loop to connect heating coil to. Set to nil for heating types besides water
    # @param fan_type [String] valid choices are ConstantVolume, Cycling
    # @param ventilation [Boolean] If true, ventilation will be supplied through the unit.  If false,
    #   no ventilation will be supplied through the unit, with the expectation that it will be provided by a DOAS or separate system.
    # @return [Array<OpenStudio::Model::ZoneHVACPackagedTerminalAirConditioner>] an array of the resulting PTACs
    def self.model_add_ptac(model,
                            thermal_zones,
                            cooling_type: 'Two Speed DX AC',
                            heating_type: 'Gas',
                            hot_water_loop: nil,
                            fan_type: 'Cycling',
                            ventilation: true)
      Composers.ptac(model,
                     thermal_zones,
                     cooling_type: cooling_type,
                     heating_type: heating_type,
                     hot_water_loop: hot_water_loop,
                     fan_type: fan_type,
                     ventilation: ventilation)
    end

    # Creates a PTHP system for each zone and adds it to the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to connect to this system
    # @param fan_type [String] valid choices are ConstantVolume, Cycling
    # @param ventilation [Boolean] If true, ventilation will be supplied through the unit.  If false,
    #   no ventilation will be supplied through the unit, with the expectation that it will be provided by a DOAS or separate system.
    # @return [Array<OpenStudio::Model::ZoneHVACPackagedTerminalAirConditioner>] an array of the resulting PTACs.
    def self.model_add_pthp(model,
                            thermal_zones,
                            fan_type: 'Cycling',
                            ventilation: true)
      Composers.pthp(model, thermal_zones, fan_type: fan_type, ventilation: ventilation)
    end

    # Creates a unit heater for each zone and adds it to the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to connect to this system
    # @param hvac_op_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the HVAC Operating Schedule. Defaults to always on if nil.
    # @param fan_control_type [String] valid choices are OnOff, ConstantVolume, VariableVolume
    # @param fan_pressure_rise [Double] fan pressure rise, inH2O
    # @param heating_type [String] valid choices are NaturalGas, Gas, Electricity, Electric, DistrictHeating, DistrictHeatingWater, DistrictHeatingSteam
    # @param hot_water_loop [OpenStudio::Model::PlantLoop] hot water loop to connect to the heating coil
    # @param rated_inlet_water_temperature [Double] rated inlet water temperature in degrees Fahrenheit, default is 180F
    # @param rated_outlet_water_temperature [Double] rated outlet water temperature in degrees Fahrenheit, default is 160F
    # @param rated_inlet_air_temperature [Double] rated inlet air temperature in degrees Fahrenheit, default is 60F
    # @param rated_outlet_air_temperature [Double] rated outlet air temperature in degrees Fahrenheit, default is 100F
    # @return [Array<OpenStudio::Model::ZoneHVACUnitHeater>] an array of the resulting unit heaters.
    def self.model_add_unitheater(model,
                                  thermal_zones,
                                  hvac_op_sch: nil,
                                  fan_control_type: 'ConstantVolume',
                                  fan_pressure_rise: 0.2,
                                  heating_type: nil,
                                  hot_water_loop: nil,
                                  rated_inlet_water_temperature: 180.0,
                                  rated_outlet_water_temperature: 160.0,
                                  rated_inlet_air_temperature: 60.0,
                                  rated_outlet_air_temperature: 104.0)
      Composers.unitheater(model,
                           thermal_zones,
                           hvac_op_sch: hvac_op_sch,
                           fan_control_type: fan_control_type,
                           fan_pressure_rise: fan_pressure_rise,
                           heating_type: heating_type,
                           hot_water_loop: hot_water_loop,
                           rated_inlet_water_temperature: rated_inlet_water_temperature,
                           rated_outlet_water_temperature: rated_outlet_water_temperature,
                           rated_inlet_air_temperature: rated_inlet_air_temperature,
                           rated_outlet_air_temperature: rated_outlet_air_temperature)
    end

    # Creates a high temp radiant heater for each zone and adds it to the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to connect to this system
    # @param heating_type [String] valid choices are Gas, Electric
    # @param combustion_efficiency [Double] combustion efficiency as decimal
    # @param control_type [String] control type
    # @return [Array<OpenStudio::Model::ZoneHVACHighTemperatureRadiant>] an
    # array of the resulting radiant heaters.
    def self.model_add_high_temp_radiant(model,
                                         thermal_zones,
                                         heating_type: 'NaturalGas',
                                         combustion_efficiency: 0.8,
                                         control_type: 'MeanAirTemperature')
      Composers.high_temp_radiant(model,
                                  thermal_zones,
                                  heating_type: heating_type,
                                  combustion_efficiency: combustion_efficiency,
                                  control_type: control_type)
    end

    # Creates an evaporative cooler for each zone and adds it to the model.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to connect to this system
    # @return [Array<OpenStudio::Model::AirLoopHVAC>] the resulting evaporative coolers
    def self.model_add_evap_cooler(model, thermal_zones)
      Composers.evap_cooler(model, thermal_zones)
    end

    # Adds hydronic or electric baseboard heating to each zone.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to add baseboards to.
    # @param hot_water_loop [OpenStudio::Model::PlantLoop] The hot water loop that serves the baseboards.  If nil, baseboards are electric.
    # @return [Array<OpenStudio::Model::ZoneHVACBaseboardConvectiveElectric, OpenStudio::Model::ZoneHVACBaseboardConvectiveWater>]
    #   array of baseboard heaters.
    def self.model_add_baseboard(model, thermal_zones,
                                 hot_water_loop: nil)
      Composers.baseboard(model, thermal_zones, hot_water_loop: hot_water_loop)
    end

    # Adds Variable Refrigerant Flow system and terminal units for each zone
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to add fan coil units
    # @param ventilation [Boolean] If true, ventilation will be supplied through the unit.  If false,
    #   no ventilation will be supplied through the unit, with the expectation that it will be provided by a DOAS or separate system.
    # @return [Array<OpenStudio::Model::ZoneHVACTerminalUnitVariableRefrigerantFlow>] array of vrf units.
    def self.model_add_vrf(model, thermal_zones,
                           ventilation: false)
      Composers.vrf(model, thermal_zones, ventilation: ventilation)
    end

    # Adds four pipe fan coil units to each zone.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to add fan coil units
    # @param chilled_water_loop [OpenStudio::Model::PlantLoop] the chilled water loop that serves the fan coils.
    # @param hot_water_loop [OpenStudio::Model::PlantLoop] the hot water loop that serves the fan coils.
    #   If nil, a zero-capacity, electric heating coil set to Always-Off will be included in the unit.
    # @param ventilation [Boolean] If true, ventilation will be supplied through the unit.  If false,
    #   no ventilation will be supplied through the unit, with the expectation that it will be provided by a DOAS or separate system.
    # @param capacity_control_method [String] Capacity control method for the fan coil. Options are ConstantFanVariableFlow,
    #   CyclingFan, VariableFanVariableFlow, and VariableFanConstantFlow.  If VariableFan, the fan will be VariableVolume.
    # @return [Array<OpenStudio::Model::ZoneHVACFourPipeFanCoil>] array of fan coil units.
    def self.model_add_four_pipe_fan_coil(model,
                                          thermal_zones,
                                          chilled_water_loop,
                                          hot_water_loop: nil,
                                          ventilation: false,
                                          capacity_control_method: 'CyclingFan')
      Composers.four_pipe_fan_coil(model,
                                   thermal_zones,
                                   chilled_water_loop,
                                   hot_water_loop: hot_water_loop,
                                   ventilation: ventilation,
                                   capacity_control_method: capacity_control_method)
    end

    # Adds low temperature radiant loop systems to each zone.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to add radiant loops
    # @param hot_water_loop [OpenStudio::Model::PlantLoop] the hot water loop that serves the radiant loop.
    # @param chilled_water_loop [OpenStudio::Model::PlantLoop] the chilled water loop that serves the radiant loop.
    # @param two_pipe_system [Boolean] when set to true, it converts the default 4-pipe water plant HVAC system to a 2-pipe system.
    # @param two_pipe_control_strategy [String] Method to determine whether the loop is in heating or cooling mode
    #   'outdoor_air_lockout' - The system will be in heating below the two_pipe_lockout_temperature variable,
    #      and cooling above the two_pipe_lockout_temperature. Requires the two_pipe_lockout_temperature variable.
    #   'zone_demand' - Create EMS code to determine heating or cooling mode based on zone heating or cooling load requests.
    #      Requires thermal_zones defined.
    # @param two_pipe_lockout_temperature [Double] hot water plant lockout in degrees Fahrenheit, default 65F.
    #   Hot water plant is unavailable when outdoor drybulb is above the specified threshold.
    # @param plant_supply_water_temperature_control [Bool] Set to true if the plant supply water temperature
    #   is to be controlled else it is held constant, default to false.
    # @param plant_supply_water_temperature_control_strategy [String] Method to determine how to control the plant's supply water temperature.
    #   'outdoor_air' - Set the supply water temperature based on the outdoor air temperature.
    #   'zone_demand' - Set the supply water temperature based on the preponderance of zone demand.
    #     Requires thermal_zone defined.
    # @param hwsp_at_oat_low [Double] hot water plant supply water temperature setpoint, in F, at the outdoor low temperature.
    #   Requires
    # @param hw_oat_low [Double] outdoor drybulb air  temperature, in F, for low setpoint for hot water plant.
    # @param hwsp_at_oat_high [Double] hot water plant supply water temperature setpoint, in F, at the outdoor high temperature.
    # @param hw_oat_high [Double] outdoor drybulb air temperature, in F, for high setpoint for hot water plant.
    # @param chwsp_at_oat_low [Double] chilled water plant supply water temperature setpoint, in F, at the outdoor low temperature.
    # @param chw_oat_low [Double] outdoor drybulb air  temperature, in F, for low setpoint for chilled water plant.
    # @param chwsp_at_oat_high [Double] chilled water plant supply water temperature setpoint, in F, at the outdoor high temperature.
    # @param chw_oat_high [Double] outdoor drybulb air temperature, in F, for high setpoint for chilled water plant.
    # @param radiant_type [String] type of radiant system, floor or ceiling, to create in zone.
    # @param radiant_temperature_control_type [String] determines the controlled temperature for the radiant system
    #   options are 'MeanAirTemperature', 'MeanRadiantTemperature', 'OperativeTemperature', 'OutdoorDryBulbTemperature',
    #   'OutdoorWetBulbTemperature', 'SurfaceFaceTemperature', 'SurfaceInteriorTemperature'
    # @param radiant_setpoint_control_type [String] determines the response of the radiant system at setpoint temperature
    #   options are 'ZeroFlowPower', 'HalfFlowPower'
    # @param include_carpet [Boolean] boolean to include thin carpet tile over radiant slab, default to true
    # @param carpet_thickness_in [Double] thickness of carpet in inches
    # @param control_strategy [String] name of control strategy.  Options are 'proportional_control', 'oa_based_control',
    #   'constant_control', and 'none'.
    #   If control strategy is 'proportional_control', the method will apply the CBE radiant control sequences
    #   detailed in Raftery et al. (2017), 'A new control strategy for high thermal mass radiant systems'.
    #   If control strategy is 'oa_based_control', the method will apply native EnergyPlus objects/parameters
    #   to vary slab setpoint based on outdoor weather.
    #   If control strategy is 'constant_control', the method will apply native EnergyPlus objects/parameters to
    #   maintain a constant slab setpoint.
    #   Otherwise no control strategy will be applied and the radiant system will assume the EnergyPlus default controls.
    # @param use_zone_occupancy_for_control [Boolean] Set to true if radiant system is to use specific zone occupancy objects
    #   for CBE control strategy. If false, then it will use values in model_occ_hr_start and model_occ_hr_end
    #   for all radiant zones. default to true.
    # @param occupied_percentage_threshold [Double] the minimum fraction (0 to 1) that counts as occupied
    #   if this parameter is set, the returned ScheduleRuleset will be 0 = unoccupied, 1 = occupied
    #   otherwise the ScheduleRuleset will be the weighted fractional occupancy schedule.
    #   Only used if use_zone_occupancy_for_control is set to true.
    # @param model_occ_hr_start [Double] (Optional) Only applies if control_strategy is 'proportional_control'.
    #   Starting hour of building occupancy.
    # @param model_occ_hr_end [Double] (Optional) Only applies if control_strategy is 'proportional_control'.
    #   Ending hour of building occupancy.
    # @param proportional_gain [Double] (Optional) Only applies if control_strategy is 'proportional_control'.
    #   Proportional gain constant (recommended 0.3 or less).
    # @param switch_over_time [Double] Time limitation for when the system can switch between heating and cooling
    # @param slab_sp_at_oat_low [Double] radiant slab temperature setpoint, in F, at the outdoor high temperature.
    # @param slab_oat_low [Double] outdoor drybulb air temperature, in F, for low radiant slab setpoint.
    # @param slab_sp_at_oat_high [Double] radiant slab temperature setpoint, in F, at the outdoor low temperature.
    # @param slab_oat_high [Double] outdoor drybulb air temperature, in F, for high radiant slab setpoint.
    # @param radiant_availability_type [String] a preset that determines the availability of the radiant system
    #   options are 'all_day', 'precool', 'afternoon_shutoff', 'occupancy'
    #   If preset is set to 'all_day' radiant system is available 24 hours a day, 'precool' primarily operates
    #   radiant system during night-time hours, 'afternoon_shutoff' avoids operation during peak grid demand,
    #   and 'occupancy' operates radiant system during building occupancy hours.
    # @param radiant_lockout [Boolean] True if system contains a radiant lockout. If true, it will overwrite radiant_availability_type.
    # @param radiant_lockout_start_time [double] decimal hour of when radiant lockout starts
    #   Only used if radiant_lockout is true
    # @param radiant_lockout_end_time [double] decimal hour of when radiant lockout ends
    #   Only used if radiant_lockout is true
    # @return [Array<OpenStudio::Model::ZoneHVACLowTemperatureRadiantVariableFlow>] array of radiant objects.
    # @todo Once the OpenStudio API supports it, make chilled water loops optional for heating only systems
    # @todo Lookup occupany start and end hours from zone occupancy schedule
    def self.model_add_low_temp_radiant(model,
                                        thermal_zones,
                                        hot_water_loop,
                                        chilled_water_loop,
                                        two_pipe_system: false,
                                        two_pipe_control_strategy: 'outdoor_air_lockout',
                                        two_pipe_lockout_temperature: 65.0,
                                        plant_supply_water_temperature_control: false,
                                        plant_supply_water_temperature_control_strategy: 'outdoor_air',
                                        hwsp_at_oat_low: 120.0,
                                        hw_oat_low: 55.0,
                                        hwsp_at_oat_high: 80.0,
                                        hw_oat_high: 70.0,
                                        chwsp_at_oat_low: 70.0,
                                        chw_oat_low: 65.0,
                                        chwsp_at_oat_high: 55.0,
                                        chw_oat_high: 75.0,
                                        radiant_type: 'floor',
                                        radiant_temperature_control_type: 'SurfaceFaceTemperature',
                                        radiant_setpoint_control_type: 'ZeroFlowPower',
                                        include_carpet: true,
                                        carpet_thickness_in: 0.25,
                                        control_strategy: 'proportional_control',
                                        use_zone_occupancy_for_control: true,
                                        occupied_percentage_threshold: 0.10,
                                        model_occ_hr_start: 6.0,
                                        model_occ_hr_end: 18.0,
                                        proportional_gain: 0.3,
                                        switch_over_time: 24.0,
                                        slab_sp_at_oat_low: 73,
                                        slab_oat_low: 65,
                                        slab_sp_at_oat_high: 68,
                                        slab_oat_high: 80,
                                        radiant_availability_type: 'precool',
                                        radiant_lockout: false,
                                        radiant_lockout_start_time: 12.0,
                                        radiant_lockout_end_time: 20.0)
      # create internal source constructions for surfaces
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Model.Model', "Replacing #{radiant_type} constructions with new radiant slab constructions.")

      # determine construction insulation thickness by climate zone
      climate_zone_number = OpenstudioStandards::Weather.model_get_ashrae_climate_zone_number(model)
      if climate_zone_number.nil?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Model.Model', 'Unable to determine climate zone for radiant slab insulation determination.  Defaulting to climate zone 5, R-20 insulation, 110F heating design supply water temperature.')
        cz_mult = 4
        radiant_htg_dsgn_sup_wtr_temp_f = 110
      else
        case climate_zone_number
        when 0, 1
          cz_mult = 2
          radiant_htg_dsgn_sup_wtr_temp_f = 90
        when 2
          cz_mult = 2
          radiant_htg_dsgn_sup_wtr_temp_f = 100
        when 3
          cz_mult = 3
          radiant_htg_dsgn_sup_wtr_temp_f = 100
        when 4
          cz_mult = 4
          radiant_htg_dsgn_sup_wtr_temp_f = 100
        when 5
          cz_mult = 4
          radiant_htg_dsgn_sup_wtr_temp_f = 110
        when 6
          cz_mult = 4
          radiant_htg_dsgn_sup_wtr_temp_f = 120
        when 7, 8
          cz_mult = 5
          radiant_htg_dsgn_sup_wtr_temp_f = 120
        else # default to 4
          cz_mult = 4
          radiant_htg_dsgn_sup_wtr_temp_f = 100
        end
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Model.Model', "Based on model climate zone #{climate_zone_number} using R-#{(cz_mult * 5).to_i} slab insulation, R-#{((cz_mult + 1) * 5).to_i} exterior floor insulation, R-#{((cz_mult + 1) * 2 * 5).to_i} exterior roof insulation, and #{radiant_htg_dsgn_sup_wtr_temp_f}F heating design supply water temperature.")
      end

      # create materials
      mat_concrete_3_5in = OpenStudio::Model::StandardOpaqueMaterial.new(model, 'MediumRough', 0.0889, 2.31, 2322, 832)
      mat_concrete_3_5in.setName('Radiant Slab Concrete - 3.5 in.')

      mat_concrete_1_5in = OpenStudio::Model::StandardOpaqueMaterial.new(model, 'MediumRough', 0.0381, 2.31, 2322, 832)
      mat_concrete_1_5in.setName('Radiant Slab Concrete - 1.5 in')

      mat_refl_roof_membrane = model.getStandardOpaqueMaterialByName('Roof Membrane - Highly Reflective')
      if mat_refl_roof_membrane.is_initialized
        mat_refl_roof_membrane = model.getStandardOpaqueMaterialByName('Roof Membrane - Highly Reflective').get
      else
        mat_refl_roof_membrane = OpenStudio::Model::StandardOpaqueMaterial.new(model, 'VeryRough', 0.0095, 0.16, 1121.29, 1460)
        mat_refl_roof_membrane.setThermalAbsorptance(0.75)
        mat_refl_roof_membrane.setSolarAbsorptance(0.45)
        mat_refl_roof_membrane.setVisibleAbsorptance(0.7)
        mat_refl_roof_membrane.setName('Roof Membrane - Highly Reflective')
      end

      if include_carpet
        carpet_thickness_m = OpenStudio.convert(carpet_thickness_in / 12.0, 'ft', 'm').get
        conductivity_si = 0.06
        conductivity_ip = OpenStudio.convert(conductivity_si, 'W/m*K', 'Btu*in/hr*ft^2*R').get
        r_value_ip = carpet_thickness_in * (1 / conductivity_ip)
        mat_thin_carpet_tile = OpenStudio::Model::StandardOpaqueMaterial.new(model, 'MediumRough', carpet_thickness_m, conductivity_si, 288, 1380)
        mat_thin_carpet_tile.setThermalAbsorptance(0.9)
        mat_thin_carpet_tile.setSolarAbsorptance(0.7)
        mat_thin_carpet_tile.setVisibleAbsorptance(0.8)
        mat_thin_carpet_tile.setName("Radiant Slab Thin Carpet Tile R-#{r_value_ip.round(2)}")
      end

      # set exterior slab insulation thickness based on climate zone
      slab_insulation_thickness_m = 0.0254 * cz_mult
      mat_slab_insulation = OpenStudio::Model::StandardOpaqueMaterial.new(model, 'Rough', slab_insulation_thickness_m, 0.02, 56.06, 1210)
      mat_slab_insulation.setName("Radiant Ground Slab Insulation - #{cz_mult} in.")

      ext_insulation_thickness_m = 0.0254 * (cz_mult + 1)
      mat_ext_insulation = OpenStudio::Model::StandardOpaqueMaterial.new(model, 'Rough', ext_insulation_thickness_m, 0.02, 56.06, 1210)
      mat_ext_insulation.setName("Radiant Exterior Slab Insulation - #{cz_mult + 1} in.")

      roof_insulation_thickness_m = 0.0254 * (cz_mult + 1) * 2
      mat_roof_insulation = OpenStudio::Model::StandardOpaqueMaterial.new(model, 'Rough', roof_insulation_thickness_m, 0.02, 56.06, 1210)
      mat_roof_insulation.setName("Radiant Exterior Ceiling Insulation - #{(cz_mult + 1) * 2} in.")

      # create radiant internal source constructions
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Model.Model', 'New constructions exclude the metal deck, as high thermal diffusivity materials cause errors in EnergyPlus internal source construction calculations.')

      layers = []
      layers << mat_slab_insulation
      layers << mat_concrete_3_5in
      layers << mat_concrete_1_5in
      layers << mat_thin_carpet_tile if include_carpet
      radiant_ground_slab_construction = OpenStudio::Model::ConstructionWithInternalSource.new(layers)
      radiant_ground_slab_construction.setName('Radiant Ground Slab Construction')
      radiant_ground_slab_construction.setSourcePresentAfterLayerNumber(2)
      radiant_ground_slab_construction.setTemperatureCalculationRequestedAfterLayerNumber(3)
      radiant_ground_slab_construction.setTubeSpacing(0.2286) # 9 inches

      layers = []
      layers << mat_ext_insulation
      layers << mat_concrete_3_5in
      layers << mat_concrete_1_5in
      layers << mat_thin_carpet_tile if include_carpet
      radiant_exterior_slab_construction = OpenStudio::Model::ConstructionWithInternalSource.new(layers)
      radiant_exterior_slab_construction.setName('Radiant Exterior Slab Construction')
      radiant_exterior_slab_construction.setSourcePresentAfterLayerNumber(2)
      radiant_exterior_slab_construction.setTemperatureCalculationRequestedAfterLayerNumber(3)
      radiant_exterior_slab_construction.setTubeSpacing(0.2286) # 9 inches

      layers = []
      layers << mat_concrete_3_5in
      layers << mat_concrete_1_5in
      layers << mat_thin_carpet_tile if include_carpet
      radiant_interior_floor_slab_construction = OpenStudio::Model::ConstructionWithInternalSource.new(layers)
      radiant_interior_floor_slab_construction.setName('Radiant Interior Floor Slab Construction')
      radiant_interior_floor_slab_construction.setSourcePresentAfterLayerNumber(1)
      radiant_interior_floor_slab_construction.setTemperatureCalculationRequestedAfterLayerNumber(1)
      radiant_interior_floor_slab_construction.setTubeSpacing(0.2286) # 9 inches

      # create reversed interior floor construction
      rev_radiant_interior_floor_slab_construction = OpenStudio::Model::ConstructionWithInternalSource.new(layers.reverse)
      rev_radiant_interior_floor_slab_construction.setName('Radiant Interior Floor Slab Construction - Reversed')
      rev_radiant_interior_floor_slab_construction.setSourcePresentAfterLayerNumber(layers.length - 1)
      rev_radiant_interior_floor_slab_construction.setTemperatureCalculationRequestedAfterLayerNumber(layers.length - 1)
      rev_radiant_interior_floor_slab_construction.setTubeSpacing(0.2286) # 9 inches

      layers = []
      layers << mat_thin_carpet_tile if include_carpet
      layers << mat_concrete_3_5in
      layers << mat_concrete_1_5in
      radiant_interior_ceiling_slab_construction = OpenStudio::Model::ConstructionWithInternalSource.new(layers)
      radiant_interior_ceiling_slab_construction.setName('Radiant Interior Ceiling Slab Construction')
      slab_src_loc = include_carpet ? 2 : 1
      radiant_interior_ceiling_slab_construction.setSourcePresentAfterLayerNumber(slab_src_loc)
      radiant_interior_ceiling_slab_construction.setTemperatureCalculationRequestedAfterLayerNumber(slab_src_loc)
      radiant_interior_ceiling_slab_construction.setTubeSpacing(0.2286) # 9 inches

      # create reversed interior ceiling construction
      rev_radiant_interior_ceiling_slab_construction = OpenStudio::Model::ConstructionWithInternalSource.new(layers.reverse)
      rev_radiant_interior_ceiling_slab_construction.setName('Radiant Interior Ceiling Slab Construction - Reversed')
      rev_radiant_interior_ceiling_slab_construction.setSourcePresentAfterLayerNumber(layers.length - slab_src_loc)
      rev_radiant_interior_ceiling_slab_construction.setTemperatureCalculationRequestedAfterLayerNumber(layers.length - slab_src_loc)
      rev_radiant_interior_ceiling_slab_construction.setTubeSpacing(0.2286) # 9 inches

      layers = []
      layers << mat_refl_roof_membrane
      layers << mat_roof_insulation
      layers << mat_concrete_3_5in
      layers << mat_concrete_1_5in
      radiant_ceiling_slab_construction = OpenStudio::Model::ConstructionWithInternalSource.new(layers)
      radiant_ceiling_slab_construction.setName('Radiant Exterior Ceiling Slab Construction')
      radiant_ceiling_slab_construction.setSourcePresentAfterLayerNumber(3)
      radiant_ceiling_slab_construction.setTemperatureCalculationRequestedAfterLayerNumber(4)
      radiant_ceiling_slab_construction.setTubeSpacing(0.2286) # 9 inches

      # adjust hot and chilled water loop temperatures and set new setpoint schedules
      radiant_htg_dsgn_sup_wtr_temp_delt_r = 10.0
      radiant_htg_dsgn_sup_wtr_temp_c = OpenStudio.convert(radiant_htg_dsgn_sup_wtr_temp_f, 'F', 'C').get
      radiant_htg_dsgn_sup_wtr_temp_delt_k = OpenStudio.convert(radiant_htg_dsgn_sup_wtr_temp_delt_r, 'R', 'K').get
      hot_water_loop.sizingPlant.setDesignLoopExitTemperature(radiant_htg_dsgn_sup_wtr_temp_c)
      hot_water_loop.sizingPlant.setLoopDesignTemperatureDifference(radiant_htg_dsgn_sup_wtr_temp_delt_k)
      hw_temp_sch = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                    radiant_htg_dsgn_sup_wtr_temp_c,
                                                                                    name: "#{hot_water_loop.name} Temp - #{radiant_htg_dsgn_sup_wtr_temp_f.round(0)}F",
                                                                                    schedule_type_limit: 'Temperature')
      hot_water_loop.supplyOutletNode.setpointManagers.each do |spm|
        if spm.to_SetpointManagerScheduled.is_initialized
          spm = spm.to_SetpointManagerScheduled.get
          spm.setSchedule(hw_temp_sch)
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Changing hot water loop setpoint for '#{hot_water_loop.name}' to '#{hw_temp_sch.name}' to account for the radiant system.")
        end
      end

      radiant_clg_dsgn_sup_wtr_temp_f = 55.0
      radiant_clg_dsgn_sup_wtr_temp_delt_r = 5.0
      radiant_clg_dsgn_sup_wtr_temp_c = OpenStudio.convert(radiant_clg_dsgn_sup_wtr_temp_f, 'F', 'C').get
      radiant_clg_dsgn_sup_wtr_temp_delt_k = OpenStudio.convert(radiant_clg_dsgn_sup_wtr_temp_delt_r, 'R', 'K').get
      chilled_water_loop.sizingPlant.setDesignLoopExitTemperature(radiant_clg_dsgn_sup_wtr_temp_c)
      chilled_water_loop.sizingPlant.setLoopDesignTemperatureDifference(radiant_clg_dsgn_sup_wtr_temp_delt_k)
      chw_temp_sch = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                     radiant_clg_dsgn_sup_wtr_temp_c,
                                                                                     name: "#{chilled_water_loop.name} Temp - #{radiant_clg_dsgn_sup_wtr_temp_f.round(0)}F",
                                                                                     schedule_type_limit: 'Temperature')
      chilled_water_loop.supplyOutletNode.setpointManagers.each do |spm|
        if spm.to_SetpointManagerScheduled.is_initialized
          spm = spm.to_SetpointManagerScheduled.get
          spm.setSchedule(chw_temp_sch)
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Changing chilled water loop setpoint for '#{chilled_water_loop.name}' to '#{chw_temp_sch.name}' to account for the radiant system.")
        end
      end

      # default temperature controls for radiant system
      zn_radiant_htg_dsgn_temp_f = 68.0
      zn_radiant_htg_dsgn_temp_c = OpenStudio.convert(zn_radiant_htg_dsgn_temp_f, 'F', 'C').get
      zn_radiant_clg_dsgn_temp_f = 74.0
      zn_radiant_clg_dsgn_temp_c = OpenStudio.convert(zn_radiant_clg_dsgn_temp_f, 'F', 'C').get

      htg_control_temp_sch = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                             zn_radiant_htg_dsgn_temp_c,
                                                                                             name: "Zone Radiant Loop Heating Threshold Temperature Schedule - #{zn_radiant_htg_dsgn_temp_f.round(0)}F",
                                                                                             schedule_type_limit: 'Temperature')
      clg_control_temp_sch = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                             zn_radiant_clg_dsgn_temp_c,
                                                                                             name: "Zone Radiant Loop Cooling Threshold Temperature Schedule - #{zn_radiant_clg_dsgn_temp_f.round(0)}F",
                                                                                             schedule_type_limit: 'Temperature')
      throttling_range_f = 4.0 # 2 degF on either side of control temperature
      throttling_range_c = OpenStudio.convert(throttling_range_f, 'F', 'C').get

      # create preset availability schedule for radiant loop
      radiant_avail_sch = OpenStudio::Model::ScheduleRuleset.new(model)
      radiant_avail_sch.setName('Radiant System Availability Schedule')

      unless radiant_lockout
        case radiant_availability_type.downcase
        when 'all_day'
          start_hour = 24
          start_minute = 0
          end_hour = 24
          end_minute = 0
        when 'afternoon_shutoff'
          start_hour = 15
          start_minute = 0
          end_hour = 22
          end_minute = 0
        when 'precool'
          start_hour = 10
          start_minute = 0
          end_hour = 22
          end_minute = 0
        when 'occupancy'
          start_hour = model_occ_hr_end.to_i
          start_minute = ((model_occ_hr_end % 1) * 60).to_i
          end_hour = model_occ_hr_start.to_i
          end_minute = ((model_occ_hr_start % 1) * 60).to_i
        else
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Model.Model', "Unsupported radiant availability preset '#{radiant_availability_type}'. Defaulting to all day operation.")
          start_hour = 24
          start_minute = 0
          end_hour = 24
          end_minute = 0
        end
      end

      # create custom availability schedule for radiant loop
      if radiant_lockout
        start_hour = radiant_lockout_start_time.to_i
        start_minute = ((radiant_lockout_start_time % 1) * 60).to_i
        end_hour = radiant_lockout_end_time.to_i
        end_minute = ((radiant_lockout_end_time % 1) * 60).to_i
      end

      # create availability schedules
      if end_hour > start_hour
        radiant_avail_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, start_hour, start_minute, 0), 1.0)
        radiant_avail_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, end_hour, end_minute, 0), 0.0)
        radiant_avail_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 1.0) if end_hour < 24
      elsif start_hour > end_hour
        radiant_avail_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, end_hour, end_minute, 0), 0.0)
        radiant_avail_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, start_hour, start_minute, 0), 1.0)
        radiant_avail_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 0.0) if start_hour < 24
      else
        radiant_avail_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 1.0)
      end

      # convert to a two-pipe system if required
      if two_pipe_system
        OpenstudioStandards::HVAC.model_two_pipe_loop(model, hot_water_loop, chilled_water_loop,
                                                      control_strategy: two_pipe_control_strategy,
                                                      lockout_temperature: two_pipe_lockout_temperature,
                                                      thermal_zones: thermal_zones)
      end

      # add supply water temperature control if enabled
      if plant_supply_water_temperature_control
        # add supply water temperature for heating plant loop
        OpenstudioStandards::HVAC.model_add_plant_supply_water_temperature_control(model, hot_water_loop,
                                                                                   control_strategy: plant_supply_water_temperature_control_strategy,
                                                                                   sp_at_oat_low: hwsp_at_oat_low,
                                                                                   oat_low: hw_oat_low,
                                                                                   sp_at_oat_high: hwsp_at_oat_high,
                                                                                   oat_high: hw_oat_high,
                                                                                   thermal_zones: thermal_zones)

        # add supply water temperature for cooling plant loop
        OpenstudioStandards::HVAC.model_add_plant_supply_water_temperature_control(model, chilled_water_loop,
                                                                                   control_strategy: plant_supply_water_temperature_control_strategy,
                                                                                   sp_at_oat_low: chwsp_at_oat_low,
                                                                                   oat_low: chw_oat_low,
                                                                                   sp_at_oat_high: chwsp_at_oat_high,
                                                                                   oat_high: chw_oat_high,
                                                                                   thermal_zones: thermal_zones)
      end

      # make a low temperature radiant loop for each zone
      radiant_loops = []
      thermal_zones.each do |zone|
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Adding radiant loop for #{zone.name}.")
        if zone.name.to_s.include? ':'
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.Model.Model', "Thermal zone '#{zone.name}' has a restricted character ':' in the name and will not work with some EMS and output reporting objects. Please rename the zone.")
        end

        # create radiant coils
        if hot_water_loop
          radiant_loop_htg_coil = OpenStudio::Model::CoilHeatingLowTempRadiantVarFlow.new(model, htg_control_temp_sch)
          radiant_loop_htg_coil.setName("#{zone.name} Radiant Loop Heating Coil")
          radiant_loop_htg_coil.setHeatingControlThrottlingRange(throttling_range_c)
          hot_water_loop.addDemandBranchForComponent(radiant_loop_htg_coil)
        else
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.Model.Model', 'Radiant loops require a hot water loop, but none was provided.')
        end

        if chilled_water_loop
          radiant_loop_clg_coil = OpenStudio::Model::CoilCoolingLowTempRadiantVarFlow.new(model, clg_control_temp_sch)
          radiant_loop_clg_coil.setName("#{zone.name} Radiant Loop Cooling Coil")
          radiant_loop_clg_coil.setCoolingControlThrottlingRange(throttling_range_c)
          chilled_water_loop.addDemandBranchForComponent(radiant_loop_clg_coil)
        else
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.Model.Model', 'Radiant loops require a chilled water loop, but none was provided.')
        end

        radiant_loop = OpenStudio::Model::ZoneHVACLowTempRadiantVarFlow.new(model,
                                                                            radiant_avail_sch,
                                                                            radiant_loop_htg_coil,
                                                                            radiant_loop_clg_coil)

        # assign internal source construction to floors in zone
        zone.spaces.each do |space|
          space.surfaces.each do |surface|
            if radiant_type == 'floor'
              if surface.surfaceType == 'Floor'
                if surface.outsideBoundaryCondition.include? 'Ground'
                  surface.setConstruction(radiant_ground_slab_construction)
                elsif surface.outsideBoundaryCondition == 'Outdoors'
                  surface.setConstruction(radiant_exterior_slab_construction)
                else # interior floor
                  surface.setConstruction(radiant_interior_floor_slab_construction)

                  # also assign construction to adjacent surface
                  if surface.adjacentSurface.is_initialized
                    adjacent_surface = surface.adjacentSurface.get
                    adjacent_surface.setConstruction(rev_radiant_interior_floor_slab_construction)
                  end
                end
              end
            elsif radiant_type == 'ceiling'
              if surface.surfaceType == 'RoofCeiling'
                if surface.outsideBoundaryCondition == 'Outdoors'
                  surface.setConstruction(radiant_ceiling_slab_construction)
                else # interior ceiling
                  surface.setConstruction(radiant_interior_ceiling_slab_construction)

                  # also assign construction to adjacent surface
                  if surface.adjacentSurface.is_initialized
                    adjacent_surface = surface.adjacentSurface.get
                    adjacent_surface.setConstruction(rev_radiant_interior_ceiling_slab_construction)
                  end
                end
              end
            end
          end
        end

        # radiant loop surfaces
        radiant_loop.setName("#{zone.name} Radiant Loop")
        if radiant_type == 'floor'
          radiant_loop.setRadiantSurfaceType('Floors')
        elsif radiant_type == 'ceiling'
          radiant_loop.setRadiantSurfaceType('Ceilings')
        end

        # radiant loop layout details
        radiant_loop.setHydronicTubingInsideDiameter(0.015875) # 5/8 in. ID, 3/4 in. OD
        # @todo include a method to determine tubing length in the zone
        # loop_length = 7*zone.floorArea
        # radiant_loop.setHydronicTubingLength()
        radiant_loop.setNumberofCircuits('CalculateFromCircuitLength')
        radiant_loop.setCircuitLength(106.7)

        # radiant loop temperature controls
        radiant_loop.setTemperatureControlType(radiant_temperature_control_type)

        # radiant loop setpoint temperature response
        radiant_loop.setSetpointControlType(radiant_setpoint_control_type)
        radiant_loop.addToThermalZone(zone)
        radiant_loops << radiant_loop

        # rename nodes before adding EMS code
        OpenstudioStandards::HVAC.rename_plant_loop_nodes(model)

        # set radiant loop controls
        case control_strategy.downcase
        when 'proportional_control'
          # slab setpoint varies based on previous day zone conditions
          OpenstudioStandards::HVAC.model_add_radiant_proportional_controls(model, zone, radiant_loop,
                                                                            radiant_temperature_control_type: radiant_temperature_control_type,
                                                                            use_zone_occupancy_for_control: use_zone_occupancy_for_control,
                                                                            occupied_percentage_threshold: occupied_percentage_threshold,
                                                                            model_occ_hr_start: model_occ_hr_start,
                                                                            model_occ_hr_end: model_occ_hr_end,
                                                                            proportional_gain: proportional_gain,
                                                                            switch_over_time: switch_over_time)
        when 'oa_based_control'
          # slab setpoint varies based on outdoor weather
          OpenstudioStandards::HVAC.model_add_radiant_basic_controls(model, zone, radiant_loop,
                                                                     radiant_temperature_control_type: radiant_temperature_control_type,
                                                                     slab_setpoint_oa_control: true,
                                                                     switch_over_time: switch_over_time,
                                                                     slab_sp_at_oat_low: slab_sp_at_oat_low,
                                                                     slab_oat_low: slab_oat_low,
                                                                     slab_sp_at_oat_high: slab_sp_at_oat_high,
                                                                     slab_oat_high: slab_oat_high)
        when 'constant_control'
          # constant slab setpoint control
          OpenstudioStandards::HVAC.model_add_radiant_basic_controls(model, zone, radiant_loop,
                                                                     radiant_temperature_control_type: radiant_temperature_control_type,
                                                                     slab_setpoint_oa_control: false,
                                                                     switch_over_time: switch_over_time,
                                                                     slab_sp_at_oat_low: slab_sp_at_oat_low,
                                                                     slab_oat_low: slab_oat_low,
                                                                     slab_sp_at_oat_high: slab_sp_at_oat_high,
                                                                     slab_oat_high: slab_oat_high)
        end
      end
      return radiant_loops
    end

    # Adds a window air conditioner to each zone.
    # Code adapted from: https://github.com/NREL/OpenStudio-BEopt/blob/master/measures/ResidentialHVACRoomAirConditioner/measure.rb
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to add fan coil units to.
    # @return [Array<OpenStudio::Model::ZoneHVACPackagedTerminalAirConditioner>] and array of PTACs used as window AC units
    def self.model_add_window_ac(model, thermal_zones)
      Composers.window_ac(model, thermal_zones)
    end

    # Adds a forced air furnace or central AC to each zone.
    # Default is a forced air furnace without outdoor air
    # Code adapted from:
    # https://github.com/NREL/OpenStudio-BEopt/blob/master/measures/ResidentialHVACFurnaceFuel/measure.rb
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to add fan coil units to.
    # @param heating [Boolean] if true, the unit will include a NaturalGas heating coil
    # @param cooling [Boolean] if true, the unit will include a DX cooling coil
    # @param ventilation [Boolean] if true, the unit will include an OA intake
    # @return [Array<OpenStudio::Model::AirLoopHVAC>] and array of air loops representing the furnaces
    def self.model_add_furnace_central_ac(model,
                                          thermal_zones,
                                          heating: true,
                                          cooling: false,
                                          ventilation: false)
      Composers.furnace_central_ac(model, thermal_zones, heating: heating, cooling: cooling, ventilation: ventilation)
    end

    # Adds an air source heat pump to each zone.
    # Code adapted from:
    # https://github.com/NREL/OpenStudio-BEopt/blob/master/measures/ResidentialHVACAirSourceHeatPumpSingleSpeed/measure.rb
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to add fan coil units to.
    # @param heating [Boolean] if true, the unit will include a NaturalGas heating coil
    # @param cooling [Boolean] if true, the unit will include a DX cooling coil
    # @param ventilation [Boolean] if true, the unit will include an OA intake
    # @return [Array<OpenStudio::Model::AirLoopHVAC>] and array of air loops representing the heat pumps
    def self.model_add_central_air_source_heat_pump(model,
                                                    thermal_zones,
                                                    heating: true,
                                                    cooling: true,
                                                    ventilation: false)
      # defaults
      hspf = 7.7
      # seer = 13.0
      # eer = 11.4
      cop = 3.05
      shr = 0.73
      ac_w_per_cfm = 0.365
      min_hp_oat_f = 0.0
      crank_case_heat_w = 0.0
      crank_case_max_temp_f = 55

      # default design temperatures across all air loops
      dsgn_temps = OpenstudioStandards::HVAC.standard_air_loop_design_sizing_temperatures

      # adjusted temperatures for furnace_central_ac
      dsgn_temps['zn_htg_dsgn_sup_air_temp_f'] = 122.0
      dsgn_temps['zn_htg_dsgn_sup_air_temp_c'] = OpenStudio.convert(dsgn_temps['zn_htg_dsgn_sup_air_temp_f'], 'F', 'C').get
      dsgn_temps['htg_dsgn_sup_air_temp_f'] = dsgn_temps['zn_htg_dsgn_sup_air_temp_f']
      dsgn_temps['htg_dsgn_sup_air_temp_c'] = dsgn_temps['zn_htg_dsgn_sup_air_temp_c']

      hps = []
      thermal_zones.each do |zone|
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Adding Central Air Source HP for #{zone.name}.")

        air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
        air_loop.setName("#{zone.name} Central Air Source HP")

        # default design settings used across all air loops
        sizing_system = OpenstudioStandards::HVAC.set_air_loop_system_sizing(air_loop, dsgn_temps, sizing_option: 'NonCoincident')
        sizing_system.setAllOutdoorAirinCooling(true)
        sizing_system.setAllOutdoorAirinHeating(true)

        # a zone with no design load still needs air flow for its own unit, see model_add_furnace_central_ac
        OpenstudioStandards::HVAC.thermal_zone_apply_residential_air_flow_floor(zone)

        # create heating coil
        htg_coil = nil
        supplemental_htg_coil = nil
        if heating
          htg_coil = OpenstudioStandards::HVAC.create_coil_heating_dx_single_speed(model,
                                                                                   name: "#{air_loop.name} heating coil",
                                                                                   type: 'Residential Central Air Source HP',
                                                                                   cop: OpenstudioStandards::HVAC.hspf_to_cop_no_fan(hspf))
          if model.version < OpenStudio::VersionString.new('3.5.0')
            htg_coil.setRatedSupplyFanPowerPerVolumeFlowRate(ac_w_per_cfm / OpenStudio.convert(1.0, 'cfm', 'm^3/s').get)
          else
            htg_coil.setRatedSupplyFanPowerPerVolumeFlowRate2017(ac_w_per_cfm / OpenStudio.convert(1.0, 'cfm', 'm^3/s').get)
          end
          htg_coil.setMinimumOutdoorDryBulbTemperatureforCompressorOperation(OpenStudio.convert(min_hp_oat_f, 'F', 'C').get)
          htg_coil.setMaximumOutdoorDryBulbTemperatureforDefrostOperation(OpenStudio.convert(40.0, 'F', 'C').get)
          htg_coil.setCrankcaseHeaterCapacity(crank_case_heat_w)
          htg_coil.setMaximumOutdoorDryBulbTemperatureforCrankcaseHeaterOperation(OpenStudio.convert(crank_case_max_temp_f, 'F', 'C').get)
          htg_coil.setDefrostStrategy('ReverseCycle')
          htg_coil.setDefrostControl('OnDemand')
          htg_coil.resetDefrostTimePeriodFraction

          # Supplemental Heating Coil

          # create supplemental heating coil
          supplemental_htg_coil = OpenstudioStandards::HVAC.create_coil_heating_electric(model,
                                                                                         name: "#{air_loop.name} Supplemental Htg Coil")
        end

        # create cooling coil
        clg_coil = nil
        if cooling
          clg_coil = OpenstudioStandards::HVAC.create_coil_cooling_dx_single_speed(model,
                                                                                   name: "#{air_loop.name} Cooling Coil",
                                                                                   type: 'Residential Central ASHP',
                                                                                   cop: cop)
          clg_coil.setRatedSensibleHeatRatio(shr)
          clg_coil.setRatedEvaporatorFanPowerPerVolumeFlowRate(OpenStudio::OptionalDouble.new(ac_w_per_cfm / OpenStudio.convert(1.0, 'cfm', 'm^3/s').get))
          clg_coil.setNominalTimeForCondensateRemovalToBegin(OpenStudio::OptionalDouble.new(1000.0))
          clg_coil.setRatioOfInitialMoistureEvaporationRateAndSteadyStateLatentCapacity(OpenStudio::OptionalDouble.new(1.5))
          clg_coil.setMaximumCyclingRate(OpenStudio::OptionalDouble.new(3.0))
          clg_coil.setLatentCapacityTimeConstant(OpenStudio::OptionalDouble.new(45.0))
          clg_coil.setCondenserType('AirCooled')
          clg_coil.setCrankcaseHeaterCapacity(OpenStudio::OptionalDouble.new(crank_case_heat_w))
          clg_coil.setMaximumOutdoorDryBulbTemperatureForCrankcaseHeaterOperation(OpenStudio::OptionalDouble.new(OpenStudio.convert(crank_case_max_temp_f, 'F', 'C').get))
        end

        # create fan
        fan = OpenstudioStandards::HVAC.create_typical_fan(model,
                                                           'Residential_HVAC_Fan',
                                                           fan_name: "#{air_loop.name} Supply Fan",
                                                           end_use_subcategory: 'Residential HVAC Fans')
        fan.setAvailabilitySchedule(model.alwaysOnDiscreteSchedule)

        # create outdoor air intake
        if ventilation
          oa_intake_controller = OpenStudio::Model::ControllerOutdoorAir.new(model)
          oa_intake_controller.setName("#{air_loop.name} OA Controller")
          oa_intake_controller.autosizeMinimumOutdoorAirFlowRate
          oa_intake_controller.resetEconomizerMinimumLimitDryBulbTemperature
          oa_intake = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(model, oa_intake_controller)
          oa_intake.setName("#{air_loop.name} OA System")
          oa_intake.addToNode(air_loop.supplyInletNode)
        end

        # create unitary system (holds the coils and fan)
        unitary = OpenStudio::Model::AirLoopHVACUnitarySystem.new(model)
        unitary.setName("#{air_loop.name} Unitary System")
        unitary.setAvailabilitySchedule(model.alwaysOnDiscreteSchedule)
        unitary.setMaximumSupplyAirTemperature(OpenStudio.convert(170.0, 'F', 'C').get) # higher temp for supplemental heat as to not severely limit its use, resulting in unmet hours.
        unitary.setMaximumOutdoorDryBulbTemperatureforSupplementalHeaterOperation(OpenStudio.convert(40.0, 'F', 'C').get)
        unitary.setControllingZoneorThermostatLocation(zone)
        unitary.addToNode(air_loop.supplyInletNode)

        # set flow rates during different conditions
        unitary.setSupplyAirFlowRateWhenNoCoolingorHeatingisRequired(0.0) unless ventilation

        # attach the coils and fan
        unitary.setHeatingCoil(htg_coil) if htg_coil
        unitary.setCoolingCoil(clg_coil) if clg_coil
        unitary.setSupplementalHeatingCoil(supplemental_htg_coil) if supplemental_htg_coil
        unitary.setSupplyFan(fan)
        unitary.setFanPlacement('BlowThrough')
        unitary.setSupplyAirFanOperatingModeSchedule(model.alwaysOffDiscreteSchedule)

        # create a diffuser
        diffuser = OpenStudio::Model::AirTerminalSingleDuctUncontrolled.new(model, model.alwaysOnDiscreteSchedule)
        diffuser.setName(" #{zone.name} Direct Air")
        air_loop.multiAddBranchForZone(zone, diffuser.to_HVACComponent.get)

        hps << air_loop
      end

      return hps
    end

    # Adds zone level water-to-air heat pumps for each zone.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones served by heat pumps
    # @param condenser_loop [OpenStudio::Model::PlantLoop] the condenser loop for the heat pumps  #
    # @param ventilation [Boolean] if true, ventilation will be supplied through the unit.
    #   If false, no ventilation will be supplied through the unit, with the expectation that it will be provided by a DOAS or separate system.
    # @return [Array<OpenStudio::Model::ZoneHVACWaterToAirHeatPump>] an array of heat pumps
    def self.model_add_water_source_hp(model,
                                       thermal_zones,
                                       condenser_loop,
                                       ventilation: true)
      Composers.water_source_hp(model, thermal_zones, condenser_loop, ventilation: ventilation)
    end

    # Adds zone level ERVs for each zone.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to add heat pumps to.
    # @return [Array<OpenStudio::Model::ZoneHVACEnergyRecoveryVentilator>] an array of zone ERVs
    # @todo review the static pressure rise for the ERV
    def self.model_add_zone_erv(model, thermal_zones)
      Composers.zone_erv(model, thermal_zones)
    end

    # Adds ideal air loads systems for each zone.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to enable ideal air loads
    # @param hvac_op_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the HVAC Operating Schedule. Defaults to always on if nil.
    # @param heat_avail_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the heating availability schedule. Defaults to always on if nil.
    # @param cool_avail_sch [OpenStudio::Model::Schedule] OpenStudio Schedule object for the cooling availability schedule. Defaults to always on if nil.
    # @param heat_limit_type [String] heating limit type
    #   options are 'NoLimit', 'LimitFlowRate', 'LimitCapacity', and 'LimitFlowRateAndCapacity'
    # @param cool_limit_type [String] cooling limit type
    #   options are 'NoLimit', 'LimitFlowRate', 'LimitCapacity', and 'LimitFlowRateAndCapacity'
    # @param dehumid_limit_type [String] dehumidification limit type
    #   options are 'None', 'ConstantSensibleHeatRatio', 'Humidistat', 'ConstantSupplyHumidityRatio'
    # @param cool_sensible_heat_ratio [Double] cooling sensible heat ratio if dehumidification limit type is 'ConstantSensibleHeatRatio'
    # @param humid_ctrl_type [String] humidification control type
    #   options are 'None', 'Humidistat', 'ConstantSupplyHumidityRatio'
    # @param include_outdoor_air [Boolean] include design specification outdoor air ventilation
    # @param enable_dcv [Boolean] include demand control ventilation, uses occupancy schedule if true
    # @param econo_ctrl_mthd [String] economizer control method (require a cool_limit_type and include_outdoor_air set to true)
    #   options are 'NoEconomizer', 'DifferentialDryBulb', 'DifferentialEnthalpy'
    # @param heat_recovery_type [String] heat recovery type
    #   options are 'None', 'Sensible', 'Enthalpy'
    # @param heat_recovery_sensible_eff [Double] heat recovery sensible effectivness if heat recovery specified
    # @param heat_recovery_latent_eff [Double] heat recovery latent effectivness if heat recovery specified
    # @param add_output_meters [Boolean] include and output custom meter objects to sum all ideal air loads values
    # @return [Array<OpenStudio::Model::ZoneHVACIdealLoadsAirSystem>] an array of ideal air loads systems
    def self.model_add_ideal_air_loads(model,
                                       thermal_zones,
                                       hvac_op_sch: nil,
                                       heat_avail_sch: nil,
                                       cool_avail_sch: nil,
                                       heat_limit_type: 'NoLimit',
                                       cool_limit_type: 'NoLimit',
                                       dehumid_limit_type: 'ConstantSensibleHeatRatio',
                                       cool_sensible_heat_ratio: 0.7,
                                       humid_ctrl_type: 'None',
                                       include_outdoor_air: true,
                                       enable_dcv: false,
                                       econo_ctrl_mthd: 'NoEconomizer',
                                       heat_recovery_type: 'None',
                                       heat_recovery_sensible_eff: 0.7,
                                       heat_recovery_latent_eff: 0.65,
                                       add_output_meters: false)
      Composers.ideal_air_loads(model,
                                thermal_zones,
                                hvac_op_sch: hvac_op_sch,
                                heat_avail_sch: heat_avail_sch,
                                cool_avail_sch: cool_avail_sch,
                                heat_limit_type: heat_limit_type,
                                cool_limit_type: cool_limit_type,
                                dehumid_limit_type: dehumid_limit_type,
                                cool_sensible_heat_ratio: cool_sensible_heat_ratio,
                                humid_ctrl_type: humid_ctrl_type,
                                include_outdoor_air: include_outdoor_air,
                                enable_dcv: enable_dcv,
                                econo_ctrl_mthd: econo_ctrl_mthd,
                                heat_recovery_type: heat_recovery_type,
                                heat_recovery_sensible_eff: heat_recovery_sensible_eff,
                                heat_recovery_latent_eff: heat_recovery_latent_eff,
                                add_output_meters: add_output_meters)
    end

    # Add a residential ERV: standalone ERV that operates to provide OA,
    # used in conjuction with a system that having mechanical cooling and a heating coil
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to enable ideal air loads
    # @return [Array<OpenStudio::Model::ZoneHVACEnergyRecoveryVentilator>] an array of zone ERVs
    def self.model_add_residential_erv(model,
                                       thermal_zones,
                                       min_oa_flow_m3_per_s_per_m2 = nil)
      Composers.residential_erv(model, thermal_zones, min_oa_flow_m3_per_s_per_m2)
    end

    # Add a residential ventilation: standalone unit ventilation and zone exhaust that operates to provide OA,
    # used in conjuction with a system that having mechanical cooling and a heating coil
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to enable ideal air loads
    # @return [Array<OpenStudio::Model::ZoneHVACUnitVentilator>] an array of zone Unit Ventilators
    def self.model_add_residential_ventilator(model,
                                              thermal_zones,
                                              min_oa_flow_m3_per_s_per_m2 = nil)
      Composers.residential_ventilator(model, thermal_zones, min_oa_flow_m3_per_s_per_m2)
    end

    # Adds an exhaust fan to each zone.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] an array of thermal zones
    # @param flow_rate [Double] the exhaust fan flow rate in m^3/s
    # @param availability_schedule [OpenStudio::Model::Schedule] OpenStudio Schedule object for the Availability Schedule. Defaults to always on if nil.
    # @param flow_fraction_schedule [OpenStudio::Model::Schedule] OpenStudio Schedule object for the flow fraction schedule
    # @param balanced_exhaust_fraction_schedule [OpenStudio::Model::Schedule] OpenStudio Schedule object for the the balanced exhaust fraction schedule
    # @return [Array<OpenStudio::Model::FanZoneExhaust>] an array of exhaust fans created
    # @todo use the create_fan_zone_exhaust method, default to 1.25 inH2O pressure rise and fan efficiency of 0.6
    def self.model_add_exhaust_fan(model,
                                   thermal_zones,
                                   flow_rate: nil,
                                   availability_schedule: nil,
                                   flow_fraction_schedule: nil,
                                   balanced_exhaust_fraction_schedule: nil)
      Composers.exhaust_fan(model,
                            thermal_zones,
                            flow_rate: flow_rate,
                            availability_schedule: availability_schedule,
                            flow_fraction_schedule: flow_fraction_schedule,
                            balanced_exhaust_fraction_schedule: balanced_exhaust_fraction_schedule)
    end

    # Adds a zone ventilation design flow rate to each zone.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] an array of thermal zones
    # @param ventilation_type [String] the zone ventilation type either Exhaust, Natural, or Intake
    # @param flow_rate [Double] the ventilation design flow rate in m^3/s
    # @param availability_schedule [OpenStudio::Model::Schedule] OpenStudio Schedule object for the Availability Schedule. Defaults to always on if nil.
    # @return [Array<OpenStudio::Model::ZoneVentilationDesignFlowRate>] an array of zone ventilation objects created
    def self.model_add_zone_ventilation(model,
                                        thermal_zones,
                                        ventilation_type: nil,
                                        flow_rate: nil,
                                        availability_schedule: nil)
      Composers.zone_ventilation(model,
                                 thermal_zones,
                                 ventilation_type: ventilation_type,
                                 flow_rate: flow_rate,
                                 availability_schedule: availability_schedule)
    end

    # Get the existing chilled water loop in the model or add a new one if there isn't one already.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param cool_fuel [String] the cooling fuel. Valid choices are Electricity, DistrictCooling, and HeatPump.
    # @param chilled_water_loop_cooling_type [String] Archetype for chilled water loops, AirCooled or WaterCooled
    def self.model_get_or_add_chilled_water_loop(model, cool_fuel,
                                                 chilled_water_loop_cooling_type: 'WaterCooled')
      # retrieve the existing chilled water loop or add a new one if necessary
      chilled_water_loop = nil
      if model.getPlantLoopByName('Chilled Water Loop').is_initialized
        chilled_water_loop = model.getPlantLoopByName('Chilled Water Loop').get
      else
        case cool_fuel
        when 'DistrictCooling'
          chilled_water_loop = OpenstudioStandards::HVAC.model_add_chw_loop(model,
                                                                            chw_pumping_configuration: 'constant primary',
                                                                            cooling_fuel: cool_fuel)
        when 'HeatPump'
          condenser_water_loop = OpenstudioStandards::HVAC.model_get_or_add_ambient_water_loop(model)
          chilled_water_loop = OpenstudioStandards::HVAC.model_add_chw_loop(model,
                                                                            chw_pumping_configuration: 'constant primary variable secondary common pipe',
                                                                            chiller_cooling_type: 'WaterCooled',
                                                                            chiller_compressor_type: 'Rotary Screw',
                                                                            condenser_water_loop: condenser_water_loop)
        when 'Electricity'
          if chilled_water_loop_cooling_type == 'AirCooled'
            chilled_water_loop = OpenstudioStandards::HVAC.model_add_chw_loop(model,
                                                                              chw_pumping_configuration: 'constant primary',
                                                                              chiller_cooling_type: 'AirCooled',
                                                                              cooling_fuel: cool_fuel)
          else

            condenser_water_loop = OpenstudioStandards::HVAC.model_add_cw_loop(model,
                                                                               cooling_tower_type: 'Open Cooling Tower',
                                                                               cooling_tower_fan_type: 'Propeller or Axial',
                                                                               cooling_tower_capacity_control: 'Variable Speed Fan',
                                                                               number_of_cells_per_tower: 1,
                                                                               number_cooling_towers: 1)
            chilled_water_loop = OpenstudioStandards::HVAC.model_add_chw_loop(model,
                                                                              chw_pumping_configuration: 'constant primary variable secondary common pipe',
                                                                              chiller_cooling_type: 'WaterCooled',
                                                                              chiller_compressor_type: 'Rotary Screw',
                                                                              condenser_water_loop: condenser_water_loop)
          end
        else
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.Model.Model', 'No cool_fuel specified.')
        end
      end

      return chilled_water_loop
    end

    # Adds supply water temperature control on specified plant water loops.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param plant_water_loop [OpenStudio::Model::PlantLoop] plant water loop to add supply water temperature control.
    # @param control_strategy [String] Method to determine how to control the plant's supply water temperature (swt).
    #   'outdoor_air' - The plant's swt will be proportional to the outdoor air based on the next 4 parameters.
    #   'zone_demand' - The plant's swt will be determined by preponderance of zone demand.
    #     Requires thermal_zone defined.
    # @param sp_at_oat_low [Double] supply water temperature setpoint, in F, at the outdoor low temperature.
    # @param oat_low [Double] outdoor drybulb air  temperature, in F, for low setpoint.
    # @param sp_at_oat_high [Double] supply water temperature setpoint, in F, at the outdoor high temperature.
    # @param oat_high [Double] outdoor drybulb air temperature, in F, for high setpoint.
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones
    def self.model_add_plant_supply_water_temperature_control(model, plant_water_loop,
                                                              control_strategy: 'outdoor_air',
                                                              sp_at_oat_low: nil,
                                                              oat_low: nil,
                                                              sp_at_oat_high: nil,
                                                              oat_high: nil,
                                                              thermal_zones: [])
      # check that all required temperature parameters are defined
      if sp_at_oat_low.nil? && oat_low.nil? && sp_at_oat_high.nil? && oat_high.nil?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', 'At least one of the required temperature parameter is nil.')
      end

      # remove any existing setpoint manager on the plant water loop
      exisiting_setpoint_managers = plant_water_loop.loopTemperatureSetpointNode.setpointManagers
      exisiting_setpoint_managers.each(&:disconnect)

      if control_strategy == 'outdoor_air'
        # create supply water temperature setpoint managers for plant based on outdoor temperature
        water_loop_setpoint_manager = OpenStudio::Model::SetpointManagerOutdoorAirReset.new(model)
        water_loop_setpoint_manager.setName("#{plant_water_loop.name.get} Supply Water Temperature Control")
        water_loop_setpoint_manager.setControlVariable('Temperature')
        water_loop_setpoint_manager.setSetpointatOutdoorLowTemperature(OpenStudio.convert(sp_at_oat_low, 'F', 'C').get)
        water_loop_setpoint_manager.setOutdoorLowTemperature(OpenStudio.convert(oat_low, 'F', 'C').get)
        water_loop_setpoint_manager.setSetpointatOutdoorHighTemperature(OpenStudio.convert(sp_at_oat_high, 'F', 'C').get)
        water_loop_setpoint_manager.setOutdoorHighTemperature(OpenStudio.convert(oat_high, 'F', 'C').get)
        water_loop_setpoint_manager.addToNode(plant_water_loop.loopTemperatureSetpointNode)
      else
        # create supply water temperature setpoint managers for plant based on zone heating and cooling demand
        # check if zone heat and cool requests program exists, if not create it
        determine_zone_cooling_needs_prg = model.getEnergyManagementSystemProgramByName('Determine_Zone_Cooling_Needs')
        determine_zone_heating_needs_prg = model.getEnergyManagementSystemProgramByName('Determine_Zone_Heating_Needs')
        unless determine_zone_cooling_needs_prg.is_initialized && determine_zone_heating_needs_prg.is_initialized
          OpenstudioStandards::HVAC.model_add_zone_heat_cool_request_count_program(model, thermal_zones)
        end

        plant_water_loop_name = OpenstudioStandards::HVAC.ems_friendly_name(plant_water_loop.name)

        if plant_water_loop.componentType.valueName == 'Heating'
          swt_upper_limit = sp_at_oat_low.nil? ? OpenStudio.convert(120, 'F', 'C').get : OpenStudio.convert(sp_at_oat_low, 'F', 'C').get
          swt_lower_limit = sp_at_oat_high.nil? ? OpenStudio.convert(80, 'F', 'C').get : OpenStudio.convert(sp_at_oat_high, 'F', 'C').get
          swt_init = OpenStudio.convert(100, 'F', 'C').get
          zone_demand_var = 'Zone_Heating_Ratio'
          swt_inc_condition_var = '> 0.70'
          swt_dec_condition_var = '< 0.30'
        else
          swt_upper_limit = sp_at_oat_low.nil? ? OpenStudio.convert(70, 'F', 'C').get : OpenStudio.convert(sp_at_oat_low, 'F', 'C').get
          swt_lower_limit = sp_at_oat_high.nil? ? OpenStudio.convert(55, 'F', 'C').get : OpenStudio.convert(sp_at_oat_high, 'F', 'C').get
          swt_init = OpenStudio.convert(62, 'F', 'C').get
          zone_demand_var = 'Zone_Cooling_Ratio'
          swt_inc_condition_var = '< 0.30'
          swt_dec_condition_var = '> 0.70'
        end

        # plant loop supply water control actuator
        sch_plant_swt_ctrl = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                             swt_init,
                                                                                             name: "#{plant_water_loop_name}_Sch_Supply_Water_Temperature",
                                                                                             schedule_type_limit: 'Temperature')

        cmd_plant_water_ctrl = OpenStudio::Model::EnergyManagementSystemActuator.new(sch_plant_swt_ctrl,
                                                                                     'Schedule:Year',
                                                                                     'Schedule Value')
        cmd_plant_water_ctrl.setName("#{plant_water_loop_name}_supply_water_ctrl")

        # create plant loop setpoint manager
        water_loop_setpoint_manager = OpenStudio::Model::SetpointManagerScheduled.new(model,
                                                                                      sch_plant_swt_ctrl)
        water_loop_setpoint_manager.setName("#{plant_water_loop.name.get} Supply Water Temperature Control")
        water_loop_setpoint_manager.setControlVariable('Temperature')
        water_loop_setpoint_manager.addToNode(plant_water_loop.loopTemperatureSetpointNode)

        # add uninitialized variables into constant program
        set_constant_values_prg_body = <<-EMS
          SET #{plant_water_loop_name}_supply_water_ctrl = #{swt_init}
        EMS

        set_constant_values_prg = model.getEnergyManagementSystemProgramByName('Set_Plant_Constant_Values')
        if set_constant_values_prg.is_initialized
          set_constant_values_prg = set_constant_values_prg.get
          set_constant_values_prg.addLine(set_constant_values_prg_body)
        else
          set_constant_values_prg = OpenStudio::Model::EnergyManagementSystemProgram.new(model)
          set_constant_values_prg.setName('Set_Plant_Constant_Values')
          set_constant_values_prg.setBody(set_constant_values_prg_body)
        end

        # program for supply water temperature control in the plot
        determine_plant_swt_prg = OpenStudio::Model::EnergyManagementSystemProgram.new(model)
        determine_plant_swt_prg.setName("Determine_#{plant_water_loop_name}_Supply_Water_Temperature")
        determine_plant_swt_prg_body = <<-EMS
          SET SWT_Increase = 1,
          SET SWT_Decrease = 1,
          SET SWT_upper_limit = #{swt_upper_limit},
          SET SWT_lower_limit = #{swt_lower_limit},
          IF #{zone_demand_var} #{swt_inc_condition_var} && (@Mod CurrentTime 1) == 0,
            SET #{plant_water_loop_name}_supply_water_ctrl = #{plant_water_loop_name}_supply_water_ctrl + SWT_Increase,
          ELSEIF #{zone_demand_var} #{swt_dec_condition_var} && (@Mod CurrentTime 1) == 0,
            SET #{plant_water_loop_name}_supply_water_ctrl = #{plant_water_loop_name}_supply_water_ctrl - SWT_Decrease,
          ELSE,
            SET #{plant_water_loop_name}_supply_water_ctrl = #{plant_water_loop_name}_supply_water_ctrl,
          ENDIF,
          IF #{plant_water_loop_name}_supply_water_ctrl > SWT_upper_limit,
            SET #{plant_water_loop_name}_supply_water_ctrl = SWT_upper_limit
          ENDIF,
          IF #{plant_water_loop_name}_supply_water_ctrl < SWT_lower_limit,
            SET #{plant_water_loop_name}_supply_water_ctrl = SWT_lower_limit
          ENDIF
        EMS
        determine_plant_swt_prg.setBody(determine_plant_swt_prg_body)

        # create EMS program manager objects
        programs_at_beginning_of_timestep = OpenStudio::Model::EnergyManagementSystemProgramCallingManager.new(model)
        programs_at_beginning_of_timestep.setName("#{plant_water_loop_name}_Demand_Based_Supply_Water_Temperature_At_Beginning_Of_Timestep")
        programs_at_beginning_of_timestep.setCallingPoint('BeginTimestepBeforePredictor')
        programs_at_beginning_of_timestep.addProgram(determine_plant_swt_prg)

        initialize_constant_parameters = model.getEnergyManagementSystemProgramCallingManagerByName('Initialize_Constant_Parameters')
        if initialize_constant_parameters.is_initialized
          initialize_constant_parameters = initialize_constant_parameters.get
          # add program if it does not exist in manager
          existing_program_names = initialize_constant_parameters.programs.collect { |prg| prg.name.get.downcase }
          unless existing_program_names.include? set_constant_values_prg.name.get.downcase
            initialize_constant_parameters.addProgram(set_constant_values_prg)
          end
        else
          initialize_constant_parameters = OpenStudio::Model::EnergyManagementSystemProgramCallingManager.new(model)
          initialize_constant_parameters.setName('Initialize_Constant_Parameters')
          initialize_constant_parameters.setCallingPoint('BeginNewEnvironment')
          initialize_constant_parameters.addProgram(set_constant_values_prg)
        end

        initialize_constant_parameters_after_warmup = model.getEnergyManagementSystemProgramCallingManagerByName('Initialize_Constant_Parameters_After_Warmup')
        if initialize_constant_parameters_after_warmup.is_initialized
          initialize_constant_parameters_after_warmup = initialize_constant_parameters_after_warmup.get
          # add program if it does not exist in manager
          existing_program_names = initialize_constant_parameters_after_warmup.programs.collect { |prg| prg.name.get.downcase }
          unless existing_program_names.include? set_constant_values_prg.name.get.downcase
            initialize_constant_parameters_after_warmup.addProgram(set_constant_values_prg)
          end
        else
          initialize_constant_parameters_after_warmup = OpenStudio::Model::EnergyManagementSystemProgramCallingManager.new(model)
          initialize_constant_parameters_after_warmup.setName('Initialize_Constant_Parameters_After_Warmup')
          initialize_constant_parameters_after_warmup.setCallingPoint('AfterNewEnvironmentWarmUpIsComplete')
          initialize_constant_parameters_after_warmup.addProgram(set_constant_values_prg)
        end
      end
    end

    # Make EMS program that will compare 'measured' zone air temperatures to thermostats
    # setpoint to determine if zone needs cooling or heating. Program will output the total
    # zones needing heating and cooling and the their ratio using the total number of zones.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] array of zones to dictate cooling or heating mode of water plant
    def self.model_add_zone_heat_cool_request_count_program(model, thermal_zones)
      # create container schedules to hold number of zones needing heating and cooling
      sch_zones_needing_heating = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                                  0,
                                                                                                  name: 'Zones Needing Heating Count Schedule',
                                                                                                  schedule_type_limit: 'Dimensionless')

      zone_needing_heating_actuator = OpenStudio::Model::EnergyManagementSystemActuator.new(sch_zones_needing_heating,
                                                                                            'Schedule:Year',
                                                                                            'Schedule Value')
      zone_needing_heating_actuator.setName('Zones_Needing_Heating')

      sch_zones_needing_cooling = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                                  0,
                                                                                                  name: 'Zones Needing Cooling Count Schedule',
                                                                                                  schedule_type_limit: 'Dimensionless')

      zone_needing_cooling_actuator = OpenStudio::Model::EnergyManagementSystemActuator.new(sch_zones_needing_cooling,
                                                                                            'Schedule:Year',
                                                                                            'Schedule Value')
      zone_needing_cooling_actuator.setName('Zones_Needing_Cooling')

      # create container schedules to hold ratio of zones needing heating and cooling
      sch_zones_needing_heating_ratio = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                                        0,
                                                                                                        name: 'Zones Needing Heating Ratio Schedule',
                                                                                                        schedule_type_limit: 'Dimensionless')

      zone_needing_heating_ratio_actuator = OpenStudio::Model::EnergyManagementSystemActuator.new(sch_zones_needing_heating_ratio,
                                                                                                  'Schedule:Year',
                                                                                                  'Schedule Value')
      zone_needing_heating_ratio_actuator.setName('Zone_Heating_Ratio')

      sch_zones_needing_cooling_ratio = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                                        0,
                                                                                                        name: 'Zones Needing Cooling Ratio Schedule',
                                                                                                        schedule_type_limit: 'Dimensionless')

      zone_needing_cooling_ratio_actuator = OpenStudio::Model::EnergyManagementSystemActuator.new(sch_zones_needing_cooling_ratio,
                                                                                                  'Schedule:Year',
                                                                                                  'Schedule Value')
      zone_needing_cooling_ratio_actuator.setName('Zone_Cooling_Ratio')

      #####
      # Create EMS program to check comfort exceedances
      ####

      # initalize inner body for heating and cooling requests programs
      determine_zone_cooling_needs_prg_inner_body = ''
      determine_zone_heating_needs_prg_inner_body = ''

      thermal_zones.each do |zone|
        # get existing 'sensors'
        exisiting_ems_sensors = model.getEnergyManagementSystemSensors
        exisiting_ems_sensors_names = exisiting_ems_sensors.collect { |sensor| "#{sensor.name.get}-#{sensor.outputVariableOrMeterName}" }

        # Create zone air temperature 'sensor' for the zone.
        zone_name = OpenstudioStandards::HVAC.ems_friendly_name(zone.name)
        zone_air_sensor_name = "#{zone_name}_ctrl_temperature"

        unless exisiting_ems_sensors_names.include?("#{zone_air_sensor_name}-Zone Air Temperature")
          zone_ctrl_temperature = OpenStudio::Model::EnergyManagementSystemSensor.new(model, 'Zone Air Temperature')
          zone_ctrl_temperature.setName(zone_air_sensor_name)
          zone_ctrl_temperature.setKeyName(zone.name.get)
        end

        # check for zone thermostats
        zone_thermostat = zone.thermostatSetpointDualSetpoint
        unless zone_thermostat.is_initialized
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "Zone #{zone.name} does not have thermostats.")
          return false
        end

        zone_thermostat = zone.thermostatSetpointDualSetpoint.get
        zone_clg_thermostat = zone_thermostat.coolingSetpointTemperatureSchedule.get
        zone_htg_thermostat = zone_thermostat.heatingSetpointTemperatureSchedule.get

        # create new sensor for zone thermostat if it does not exist already
        zone_clg_thermostat_sensor_name = "#{zone_name}_upper_comfort_limit"
        zone_htg_thermostat_sensor_name = "#{zone_name}_lower_comfort_limit"

        unless exisiting_ems_sensors_names.include?("#{zone_clg_thermostat_sensor_name}-Schedule Value")
          # Upper comfort limit for the zone. Taken from existing thermostat schedules in the zone.
          zone_upper_comfort_limit = OpenStudio::Model::EnergyManagementSystemSensor.new(model, 'Schedule Value')
          zone_upper_comfort_limit.setName(zone_clg_thermostat_sensor_name)
          zone_upper_comfort_limit.setKeyName(zone_clg_thermostat.name.get)
        end

        unless exisiting_ems_sensors_names.include?("#{zone_htg_thermostat_sensor_name}-Schedule Value")
          # Lower comfort limit for the zone. Taken from existing thermostat schedules in the zone.
          zone_lower_comfort_limit = OpenStudio::Model::EnergyManagementSystemSensor.new(model, 'Schedule Value')
          zone_lower_comfort_limit.setName(zone_htg_thermostat_sensor_name)
          zone_lower_comfort_limit.setKeyName(zone_htg_thermostat.name.get)
        end

        # create program inner body for determining zone cooling needs
        if thermal_zones.include? zone
          determine_zone_cooling_needs_prg_inner_body += "IF #{zone_air_sensor_name} > #{zone_clg_thermostat_sensor_name},
                                                          SET Zones_Needing_Cooling = Zones_Needing_Cooling + 1,
                                                        ENDIF,\n"
        end

        # create program inner body for determining zone cooling needs
        if thermal_zones.include? zone
          determine_zone_heating_needs_prg_inner_body += "IF #{zone_air_sensor_name} < #{zone_htg_thermostat_sensor_name},
                                                          SET Zones_Needing_Heating = Zones_Needing_Heating + 1,
                                                        ENDIF,\n"
        end
      end

      # create program for determining zone cooling needs
      determine_zone_cooling_needs_prg = OpenStudio::Model::EnergyManagementSystemProgram.new(model)
      determine_zone_cooling_needs_prg.setName('Determine_Zone_Cooling_Needs')
      determine_zone_cooling_needs_prg_body =
        "SET Zones_Needing_Cooling = 0,
          #{determine_zone_cooling_needs_prg_inner_body}
        SET Total_Zones = #{thermal_zones.length},
        SET Zone_Cooling_Ratio = Zones_Needing_Cooling/Total_Zones"
      determine_zone_cooling_needs_prg.setBody(determine_zone_cooling_needs_prg_body)

      # create program for determining zone heating needs
      determine_zone_heating_needs_prg = OpenStudio::Model::EnergyManagementSystemProgram.new(model)
      determine_zone_heating_needs_prg.setName('Determine_Zone_Heating_Needs')
      determine_zone_heating_needs_prg_body =
        "SET Zones_Needing_Heating = 0,
          #{determine_zone_heating_needs_prg_inner_body}
        SET Total_Zones = #{thermal_zones.length},
        SET Zone_Heating_Ratio = Zones_Needing_Heating/Total_Zones"
      determine_zone_heating_needs_prg.setBody(determine_zone_heating_needs_prg_body)

      # create EMS program manager objects
      programs_at_beginning_of_timestep = OpenStudio::Model::EnergyManagementSystemProgramCallingManager.new(model)
      programs_at_beginning_of_timestep.setName('Heating_Cooling_Request_Programs_At_End_Of_Timestep')
      programs_at_beginning_of_timestep.setCallingPoint('EndOfZoneTimestepAfterZoneReporting')
      programs_at_beginning_of_timestep.addProgram(determine_zone_cooling_needs_prg)
      programs_at_beginning_of_timestep.addProgram(determine_zone_heating_needs_prg)
    end

    # Adds a waterside economizer to the chilled water and condenser loop
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param integrated [Boolean] when set to true, models an integrated waterside economizer
    #   Integrated: in series with chillers, can run simultaneously with chillers
    #   Non-Integrated: in parallel with chillers, chillers locked out during operation
    def self.model_add_waterside_economizer(model, chilled_water_loop, condenser_water_loop,
                                            integrated: true)
      # make a new heat exchanger
      heat_exchanger = OpenStudio::Model::HeatExchangerFluidToFluid.new(model)
      heat_exchanger.setHeatExchangeModelType('CounterFlow')
      # zero degree minimum necessary to allow both economizer and heat exchanger to operate in both integrated and non-integrated archetypes
      # possibly results from an EnergyPlus issue that didn't get resolved correctly https://github.com/NREL/EnergyPlus/issues/5626
      heat_exchanger.setMinimumTemperatureDifferencetoActivateHeatExchanger(OpenStudio.convert(0.0, 'R', 'K').get)
      heat_exchanger.setHeatTransferMeteringEndUseType('FreeCooling')
      heat_exchanger.setOperationMinimumTemperatureLimit(OpenStudio.convert(35.0, 'F', 'C').get)
      heat_exchanger.setOperationMaximumTemperatureLimit(OpenStudio.convert(72.0, 'F', 'C').get)
      heat_exchanger.setAvailabilitySchedule(model.alwaysOnDiscreteSchedule)

      # get the chillers on the chilled water loop
      chillers = chilled_water_loop.supplyComponents('OS:Chiller:Electric:EIR'.to_IddObjectType)

      if integrated
        if chillers.empty?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Model.Model', "No chillers were found on #{chilled_water_loop.name}; only modeling waterside economizer")
        end

        # set methods for integrated heat exchanger
        heat_exchanger.setName('Integrated Waterside Economizer Heat Exchanger')
        heat_exchanger.setControlType('CoolingDifferentialOnOff')

        # add the heat exchanger to the chilled water loop upstream of the chiller
        heat_exchanger.addToNode(chilled_water_loop.supplyInletNode)

        # Copy the setpoint managers from the plant's supply outlet node to the chillers and HX outlets.
        # This is necessary so that the correct type of operation scheme will be created.
        # Without this, OS will create an uncontrolled operation scheme and the chillers will never run.
        chw_spms = chilled_water_loop.supplyOutletNode.setpointManagers
        objs = []
        chillers.each do |obj|
          objs << obj.to_ChillerElectricEIR.get
        end
        objs << heat_exchanger
        objs.each do |obj|
          outlet = obj.supplyOutletModelObject.get.to_Node.get
          chw_spms.each do |spm|
            new_spm = spm.clone.to_SetpointManager.get
            new_spm.addToNode(outlet)
            OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Copied SPM #{spm.name} to the outlet of #{obj.name}.")
          end
        end
      else
        # non-integrated
        # if the heat exchanger can meet the entire load, the heat exchanger will run and the chiller is disabled.
        # In E+, only one chiller can be tied to a given heat exchanger, so if you have multiple chillers,
        # they will cannot be tied to a single heat exchanger without EMS.
        chiller = nil
        if chillers.empty?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Model.Model', "No chillers were found on #{chilled_water_loop.name}; cannot add a non-integrated waterside economizer.")
          heat_exchanger.setControlType('CoolingSetpointOnOff')
        elsif chillers.size > 1
          chiller = chillers.min
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Model.Model', "More than one chiller was found on #{chilled_water_loop.name}.  EnergyPlus only allows a single chiller to be interlocked with the HX.  Chiller #{chiller.name} was selected.  Additional chillers will not be locked out during HX operation.")
        else # 1 chiller
          chiller = chillers[0]
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Chiller '#{chiller.name}' will be locked out during HX operation.")
        end
        chiller = chiller.to_ChillerElectricEIR.get

        # set methods for non-integrated heat exchanger
        heat_exchanger.setName('Non-Integrated Waterside Economizer Heat Exchanger')
        heat_exchanger.setControlType('CoolingSetpointOnOffWithComponentOverride')

        # add the heat exchanger to a supply side branch of the chilled water loop parallel with the chiller(s)
        chilled_water_loop.addSupplyBranchForComponent(heat_exchanger)

        # Copy the setpoint managers from the plant's supply outlet node to the HX outlet.
        # This is necessary so that the correct type of operation scheme will be created.
        # Without this, the HX will never run
        chw_spms = chilled_water_loop.supplyOutletNode.setpointManagers
        outlet = heat_exchanger.supplyOutletModelObject.get.to_Node.get
        chw_spms.each do |spm|
          new_spm = spm.clone.to_SetpointManager.get
          new_spm.addToNode(outlet)
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Copied SPM #{spm.name} to the outlet of #{heat_exchanger.name}.")
        end

        # set the supply and demand inlet fields to interlock the heat exchanger with the chiller
        chiller_supply_inlet = chiller.supplyInletModelObject.get.to_Node.get
        heat_exchanger.setComponentOverrideLoopSupplySideInletNode(chiller_supply_inlet)
        chiller_demand_inlet = chiller.demandInletModelObject.get.to_Node.get
        heat_exchanger.setComponentOverrideLoopDemandSideInletNode(chiller_demand_inlet)

        # check if the chilled water pump is on a branch with the chiller.
        # if it is, move this pump before the splitter so that it can push water through either the chiller or the heat exchanger.
        pumps_on_branches = []
        # search for constant and variable speed pumps  between supply splitter and supply mixer.
        chilled_water_loop.supplyComponents(chilled_water_loop.supplySplitter, chilled_water_loop.supplyMixer).each do |supply_comp|
          if supply_comp.to_PumpConstantSpeed.is_initialized
            pumps_on_branches << supply_comp.to_PumpConstantSpeed.get
          elsif supply_comp.to_PumpVariableSpeed.is_initialized
            pumps_on_branches << supply_comp.to_PumpVariableSpeed.get
          end
        end
        # If only one pump is found, clone it, put the clone on the supply inlet node, and delete the original pump.
        # If multiple branch pumps, clone the first pump found, add it to the inlet of the heat exchanger, and warn user.
        if pumps_on_branches.size == 1
          pump = pumps_on_branches[0]
          pump_clone = pump.clone(model).to_StraightComponent.get
          pump_clone.addToNode(chilled_water_loop.supplyInletNode)
          pump.remove
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Model.Model', 'Since you need a pump to move water through the HX, the pump serving the chiller was moved so that it can also serve the HX depending on the desired control sequence.')
        elsif pumps_on_branches.size > 1
          hx_inlet_node = heat_exchanger.inletModelObject.get.to_Node.get
          pump = pumps_on_branches[0]
          pump_clone = pump.clone(model).to_StraightComponent.get
          pump_clone.addToNode(hx_inlet_node)
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Model.Model', 'Found 2 or more pumps on branches.  Since you need a pump to move water through the HX, the first pump encountered was copied and placed in series with the HX.  This pump might not be reasonable for this duty, please check.')
        end
      end

      # add heat exchanger to condenser water loop
      condenser_water_loop.addDemandBranchForComponent(heat_exchanger)

      # change setpoint manager on condenser water loop to allow waterside economizing
      dsgn_sup_wtr_temp_f = 42.0
      dsgn_sup_wtr_temp_c = OpenStudio.convert(dsgn_sup_wtr_temp_f, 'F', 'C').get
      condenser_water_loop.supplyOutletNode.setpointManagers.each do |spm|
        if spm.to_SetpointManagerFollowOutdoorAirTemperature.is_initialized
          spm = spm.to_SetpointManagerFollowOutdoorAirTemperature.get
          spm.setMinimumSetpointTemperature(dsgn_sup_wtr_temp_c)
        elsif spm.to_SetpointManagerScheduled.is_initialized
          spm = spm.to_SetpointManagerScheduled.get
          cw_temp_sch = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                        dsgn_sup_wtr_temp_c,
                                                                                        name: "#{chilled_water_loop.name} Temp - #{dsgn_sup_wtr_temp_f.round(0)}F",
                                                                                        schedule_type_limit: 'Temperature')
          spm.setSchedule(cw_temp_sch)
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Changing condenser water loop setpoint for '#{condenser_water_loop.name}' to '#{cw_temp_sch.name}' to account for the waterside economizer.")
        else
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Model.Model', "Condenser water loop '#{condenser_water_loop.name}' setpoint manager '#{spm.name}' is not a recognized setpoint manager type.  Cannot change to account for the waterside economizer.")
        end
      end

      OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Added #{heat_exchanger.name} to condenser water loop #{condenser_water_loop.name} and chilled water loop #{chilled_water_loop.name} to enable waterside economizing.")

      return heat_exchanger
    end

    # Get the existing hot water loop in the model or add a new one if there isn't one already.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param heat_fuel [String] the heating fuel. Valid choices are NaturalGas, Electricity, DistrictHeating, DistrictHeatingWater, DistrictHeatingSteam
    # @param hot_water_loop_type [String] Archetype for hot water loops
    #   HighTemperature (180F supply) or LowTemperature (120F supply)
    def self.model_get_or_add_hot_water_loop(model, heat_fuel,
                                             hot_water_loop_type: 'HighTemperature')
      if heat_fuel.nil?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', 'Hot water loop fuel type is nil.  Cannot add hot water loop.')
      end
      make_new_hot_water_loop = true
      hot_water_loop = nil
      # retrieve the existing hot water loop or add a new one if not of the correct type
      if model.getPlantLoopByName('Hot Water Loop').is_initialized
        hot_water_loop = model.getPlantLoopByName('Hot Water Loop').get
        design_loop_exit_temperature = hot_water_loop.sizingPlant.designLoopExitTemperature
        design_loop_exit_temperature = OpenStudio.convert(design_loop_exit_temperature, 'C', 'F').get
        # check that the loop is the correct archetype
        if hot_water_loop_type == 'HighTemperature'
          make_new_hot_water_loop = false if design_loop_exit_temperature > 130.0
        elsif hot_water_loop_type == 'LowTemperature'
          make_new_hot_water_loop = false if design_loop_exit_temperature <= 130.0
        else
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "Hot water loop archetype #{hot_water_loop_type} not recognized.")
        end
      end

      if make_new_hot_water_loop
        if hot_water_loop_type == 'HighTemperature'
          hot_water_loop = OpenstudioStandards::HVAC.model_add_hw_loop(model, heat_fuel)
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'New high temperature hot water loop created.')
        elsif hot_water_loop_type == 'LowTemperature'
          hot_water_loop = OpenstudioStandards::HVAC.model_add_hw_loop(model, heat_fuel,
                                                                       dsgn_sup_wtr_temp: 120.0,
                                                                       boiler_draft_type: 'Condensing')
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'New low temperature hot water loop created.')
        else
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "Hot water loop archetype #{hot_water_loop_type} not recognized.")
        end
      end
      return hot_water_loop
    end

    # Get the existing ambient water loop in the model or add a new one if there isn't one already.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @return [OpenStudio::Model::PlantLoop] the ambient water loop
    def self.model_get_or_add_ambient_water_loop(model)
      # retrieve the existing hot water loop or add a new one if necessary
      ambient_water_loop = if model.getPlantLoopByName('Ambient Loop').is_initialized
                             model.getPlantLoopByName('Ambient Loop').get
                           else
                             OpenstudioStandards::HVAC.model_add_district_ambient_loop(model)
                           end
      return ambient_water_loop
    end

    # Get the existing ground heat exchanger loop in the model or add a new one if there isn't one already.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @return [OpenStudio::Model::PlantLoop] the ground hx loop
    def self.model_get_or_add_ground_hx_loop(model)
      # retrieve the existing ground HX loop or add a new one if necessary
      ground_hx_loop = if model.getPlantLoopByName('Ground HX Loop').is_initialized
                         model.getPlantLoopByName('Ground HX Loop').get
                       else
                         OpenstudioStandards::HVAC.model_add_ground_hx_loop(model)
                       end
      return ground_hx_loop
    end

    # Get the existing heat pump loop in the model or add a new one if there isn't one already.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param heat_fuel [String] the heating fuel. Valid choices are NaturalGas, Electricity, DistrictHeating, DistrictHeatingWater, DistrictHeatingSteam
    # @param cool_fuel [String] the cooling fuel. Valid choices are Electricity and DistrictCooling.
    # @param heat_pump_loop_cooling_type [String] the type of cooling equipment if not DistrictCooling.
    #   Valid options are:
    #   CoolingTower, CoolingTowerSingleSpeed, CoolingTowerTwoSpeed, CoolingTowerVariableSpeed,
    #   FluidCooler, FluidCoolerSingleSpeed, FluidCoolerTwoSpeed,
    #   EvaporativeFluidCooler, EvaporativeFluidCoolerSingleSpeed, EvaporativeFluidCoolerTwoSpeed
    def self.model_get_or_add_heat_pump_loop(model, heat_fuel, cool_fuel,
                                             heat_pump_loop_cooling_type: 'EvaporativeFluidCooler')
      # retrieve the existing heat pump loop or add a new one if necessary
      heat_pump_loop = if model.getPlantLoopByName('Heat Pump Loop').is_initialized
                         model.getPlantLoopByName('Heat Pump Loop').get
                       else
                         OpenstudioStandards::HVAC.model_add_hp_loop(model, heating_fuel: heat_fuel, cooling_fuel: cool_fuel, cooling_type: heat_pump_loop_cooling_type)
                       end
      return heat_pump_loop
    end

    # Add the specified system type to the specified zones based on the specified template.
    # For multi-zone system types, add one system per story.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param system_type [String] The system type
    # @param main_heat_fuel [String] Main heating fuel used for air loops and plant loops
    # @param zone_heat_fuel [String] Zone heating fuel for zone hvac equipment and terminal units
    # @param cool_fuel [String] Cooling fuel used for air loops, plant loops, and zone equipment
    # @param zones [Array<OpenStudio::Model::ThermalZone>] array of thermal zones served by the system
    # @param hot_water_loop_type [String] Archetype for hot water loops
    #   HighTemperature (180F supply) (default) or LowTemperature (120F supply)
    #   only used if HVAC system has a hot water loop
    # @param chilled_water_loop_cooling_type [String] Archetype for chilled water loops, AirCooled or WaterCooled
    #   only used if HVAC system has a chilled water loop and cool_fuel is Electricity
    # @param heat_pump_loop_cooling_type [String] the type of cooling equipment for heat pump loops if not DistrictCooling.
    #   Valid options are:
    #   CoolingTower, CoolingTowerSingleSpeed, CoolingTowerTwoSpeed, CoolingTowerVariableSpeed,
    #   FluidCooler, FluidCoolerSingleSpeed, FluidCoolerTwoSpeed,
    #   EvaporativeFluidCooler, EvaporativeFluidCoolerSingleSpeed, EvaporativeFluidCoolerTwoSpeed
    # @param air_loop_heating_type [String] type of heating coil serving main air loop, options are Gas, DX, or Water
    # @param air_loop_cooling_type [String] type of cooling coil serving main air loop, options are DX or Water
    # @param zone_equipment_ventilation [Boolean] toggle whether to include outdoor air ventilation on zone equipment
    #   including as fan coil units, VRF terminals, or water source heat pumps.
    # @param fan_coil_capacity_control_method [String] Only applicable to Fan Coil system type.
    #   Capacity control method for the fan coil. Options are ConstantFanVariableFlow, CyclingFan, VariableFanVariableFlow,
    #   and VariableFanConstantFlow.  If VariableFan, the fan will be VariableVolume.
    # @return [Boolean] returns true if successful, false if not
    def self.model_add_hvac_system(model,
                                   system_type,
                                   main_heat_fuel,
                                   zone_heat_fuel,
                                   cool_fuel,
                                   zones,
                                   hot_water_loop_type: 'HighTemperature',
                                   chilled_water_loop_cooling_type: 'WaterCooled',
                                   heat_pump_loop_cooling_type: 'EvaporativeFluidCooler',
                                   air_loop_heating_type: 'Water',
                                   air_loop_cooling_type: 'Water',
                                   zone_equipment_ventilation: true,
                                   fan_coil_capacity_control_method: 'CyclingFan')
      # enforce defaults if fields are nil
      hot_water_loop_type = 'HighTemperature' if hot_water_loop_type.nil?
      chilled_water_loop_cooling_type = 'WaterCooled' if chilled_water_loop_cooling_type.nil?
      heat_pump_loop_cooling_type = 'EvaporativeFluidCooler' if heat_pump_loop_cooling_type.nil?
      air_loop_heating_type = 'Water' if air_loop_heating_type.nil?
      air_loop_cooling_type = 'Water' if air_loop_cooling_type.nil?
      zone_equipment_ventilation = true if zone_equipment_ventilation.nil?
      fan_coil_capacity_control_method = 'CyclingFan' if fan_coil_capacity_control_method.nil?

      # don't do anything if there are no zones
      return true if zones.empty?

      case system_type
      when 'PTAC'
        case main_heat_fuel
        when 'NaturalGas', 'DistrictHeating', 'DistrictHeatingWater', 'DistrictHeatingSteam'
          heating_type = 'Water'
          hot_water_loop = OpenstudioStandards::HVAC.model_get_or_add_hot_water_loop(model, main_heat_fuel,
                                                                                     hot_water_loop_type: hot_water_loop_type)
        when 'AirSourceHeatPump'
          heating_type = 'Water'
          hot_water_loop = OpenstudioStandards::HVAC.model_get_or_add_hot_water_loop(model, main_heat_fuel,
                                                                                     hot_water_loop_type: 'LowTemperature')
        when 'Electricity'
          heating_type = main_heat_fuel
          hot_water_loop = nil
        else
          heating_type = zone_heat_fuel
          hot_water_loop = nil
        end

        OpenstudioStandards::HVAC.model_add_ptac(model, zones,
                                                 cooling_type: 'Single Speed DX AC',
                                                 heating_type: heating_type,
                                                 hot_water_loop: hot_water_loop,
                                                 fan_type: 'Cycling',
                                                 ventilation: zone_equipment_ventilation)

      when 'PTHP'
        OpenstudioStandards::HVAC.model_add_pthp(model, zones,
                                                 fan_type: 'Cycling',
                                                 ventilation: zone_equipment_ventilation)

      when 'PSZ-AC'
        case main_heat_fuel
        when 'NaturalGas', 'Gas'
          heating_type = main_heat_fuel
          supplemental_heating_type = 'Electricity'
          if air_loop_heating_type == 'Water'
            hot_water_loop = OpenstudioStandards::HVAC.model_get_or_add_hot_water_loop(model, main_heat_fuel,
                                                                                       hot_water_loop_type: hot_water_loop_type)
            heating_type = 'Water'
          else
            hot_water_loop = nil
          end
        when 'DistrictHeating', 'DistrictHeatingWater', 'DistrictHeatingSteam'
          heating_type = 'Water'
          supplemental_heating_type = 'Electricity'
          hot_water_loop = OpenstudioStandards::HVAC.model_get_or_add_hot_water_loop(model, main_heat_fuel,
                                                                                     hot_water_loop_type: hot_water_loop_type)
        when 'AirSourceHeatPump', 'ASHP'
          heating_type = 'Water'
          supplemental_heating_type = 'Electricity'
          hot_water_loop = OpenstudioStandards::HVAC.model_get_or_add_hot_water_loop(model, main_heat_fuel,
                                                                                     hot_water_loop_type: 'LowTemperature')
        when 'Electricity'
          heating_type = main_heat_fuel
          supplemental_heating_type = 'Electricity'
        else
          heating_type = zone_heat_fuel
          supplemental_heating_type = nil
          hot_water_loop = nil
        end

        case cool_fuel
        when 'DistrictCooling'
          chilled_water_loop = OpenstudioStandards::HVAC.model_get_or_add_chilled_water_loop(model, cool_fuel)
          cooling_type = 'Water'
        else
          chilled_water_loop = nil
          cooling_type = 'Single Speed DX AC'
        end

        OpenstudioStandards::HVAC.model_add_psz_ac(model, zones,
                                                   cooling_type: cooling_type,
                                                   chilled_water_loop: chilled_water_loop,
                                                   hot_water_loop: hot_water_loop,
                                                   heating_type: heating_type,
                                                   supplemental_heating_type: supplemental_heating_type,
                                                   fan_location: 'DrawThrough',
                                                   fan_type: 'ConstantVolume')

      when 'PSZ-HP'
        OpenstudioStandards::HVAC.model_add_psz_ac(model, zones,
                                                   system_name: 'PSZ-HP',
                                                   cooling_type: 'Single Speed Heat Pump',
                                                   heating_type: 'Single Speed Heat Pump',
                                                   supplemental_heating_type: 'Electricity',
                                                   fan_location: 'DrawThrough',
                                                   fan_type: 'ConstantVolume')

      when 'PSZ-VAV'
        if main_heat_fuel.nil?
          supplemental_heating_type = nil
        else
          supplemental_heating_type = 'Electricity'
        end
        OpenstudioStandards::HVAC.model_add_psz_vav(model, zones,
                                                    system_name: 'PSZ-VAV',
                                                    heating_type: main_heat_fuel,
                                                    supplemental_heating_type: supplemental_heating_type,
                                                    hvac_op_sch: nil,
                                                    oa_damper_sch: nil)

      when 'VRF'
        OpenstudioStandards::HVAC.model_add_vrf(model, zones,
                                                ventilation: zone_equipment_ventilation)

      when 'Fan Coil'
        case main_heat_fuel
        when 'NaturalGas', 'DistrictHeating', 'DistrictHeatingWater', 'DistrictHeatingSteam', 'Electricity'
          hot_water_loop = OpenstudioStandards::HVAC.model_get_or_add_hot_water_loop(model, main_heat_fuel,
                                                                                     hot_water_loop_type: hot_water_loop_type)
        when 'AirSourceHeatPump'
          hot_water_loop = OpenstudioStandards::HVAC.model_get_or_add_hot_water_loop(model, main_heat_fuel,
                                                                                     hot_water_loop_type: 'LowTemperature')
        else
          hot_water_loop = nil
        end

        case cool_fuel
        when 'Electricity', 'DistrictCooling'
          chilled_water_loop = OpenstudioStandards::HVAC.model_get_or_add_chilled_water_loop(model, cool_fuel,
                                                                                             chilled_water_loop_cooling_type: chilled_water_loop_cooling_type)
        else
          chilled_water_loop = nil
        end

        OpenstudioStandards::HVAC.model_add_four_pipe_fan_coil(model, zones, chilled_water_loop,
                                                               hot_water_loop: hot_water_loop,
                                                               ventilation: zone_equipment_ventilation,
                                                               capacity_control_method: fan_coil_capacity_control_method)

      when 'Radiant Slab'
        case main_heat_fuel
        when 'NaturalGas', 'DistrictHeating', 'DistrictHeatingWater', 'DistrictHeatingSteam', 'Electricity'
          hot_water_loop = OpenstudioStandards::HVAC.model_get_or_add_hot_water_loop(model, main_heat_fuel,
                                                                                     hot_water_loop_type: hot_water_loop_type)
        when 'AirSourceHeatPump'
          hot_water_loop = OpenstudioStandards::HVAC.model_get_or_add_hot_water_loop(model, main_heat_fuel,
                                                                                     hot_water_loop_type: 'LowTemperature')
        else
          hot_water_loop = nil
        end

        case cool_fuel
        when 'Electricity', 'DistrictCooling'
          chilled_water_loop = OpenstudioStandards::HVAC.model_get_or_add_chilled_water_loop(model, cool_fuel,
                                                                                             chilled_water_loop_cooling_type: chilled_water_loop_cooling_type)
        else
          chilled_water_loop = nil
        end

        OpenstudioStandards::HVAC.model_add_low_temp_radiant(model,
                                                             zones,
                                                             hot_water_loop,
                                                             chilled_water_loop)

      when 'Baseboards'
        case main_heat_fuel
        when 'NaturalGas', 'DistrictHeating', 'DistrictHeatingWater', 'DistrictHeatingSteam'
          hot_water_loop = OpenstudioStandards::HVAC.model_get_or_add_hot_water_loop(model, main_heat_fuel,
                                                                                     hot_water_loop_type: hot_water_loop_type)
        when 'AirSourceHeatPump'
          hot_water_loop = OpenstudioStandards::HVAC.model_get_or_add_hot_water_loop(model, main_heat_fuel,
                                                                                     hot_water_loop_type: 'LowTemperature')
        when 'Electricity'
          hot_water_loop = nil
        else
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', 'Baseboards must have heating_type specified.')
          return false
        end
        OpenstudioStandards::HVAC.model_add_baseboard(model, zones,
                                                      hot_water_loop: hot_water_loop)

      when 'Unit Heaters'
        OpenstudioStandards::HVAC.model_add_unitheater(model, zones,
                                                       hvac_op_sch: nil,
                                                       fan_control_type: 'ConstantVolume',
                                                       fan_pressure_rise: 0.2,
                                                       heating_type: main_heat_fuel)

      when 'High Temp Radiant'
        OpenstudioStandards::HVAC.model_add_high_temp_radiant(model, zones,
                                                              heating_type: main_heat_fuel,
                                                              combustion_efficiency: 0.8)

      when 'Window AC'
        OpenstudioStandards::HVAC.model_add_window_ac(model, zones)

      when 'Residential AC'
        OpenstudioStandards::HVAC.model_add_furnace_central_ac(model, zones,
                                                               heating: false,
                                                               cooling: true,
                                                               ventilation: false)

      when 'Forced Air Furnace'
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Model.Model', 'If a Forced Air Furnace with ventilation serves a core zone, make sure the outdoor air is included in design sizing for the systems (typically occupancy, and therefore ventilation is zero during winter sizing), otherwise it may not be sized large enough to meet the heating load in some situations.')
        OpenstudioStandards::HVAC.model_add_furnace_central_ac(model, zones,
                                                               heating: true,
                                                               cooling: false,
                                                               ventilation: true)

      when 'Residential Forced Air Furnace'
        OpenstudioStandards::HVAC.model_add_furnace_central_ac(model, zones,
                                                               heating: true,
                                                               cooling: false,
                                                               ventilation: false)

      when 'Residential Forced Air Furnace with AC'
        OpenstudioStandards::HVAC.model_add_furnace_central_ac(model, zones,
                                                               heating: true,
                                                               cooling: true,
                                                               ventilation: false)

      when 'Residential Air Source Heat Pump'
        heating = true unless main_heat_fuel.nil?
        cooling = true unless cool_fuel.nil?
        OpenstudioStandards::HVAC.model_add_central_air_source_heat_pump(model, zones,
                                                                         heating: heating,
                                                                         cooling: cooling,
                                                                         ventilation: false)

      when 'Residential Minisplit Heat Pumps'
        OpenstudioStandards::HVAC.model_add_minisplit_hp(model, zones)

      when 'VAV Reheat'
        case main_heat_fuel
        when 'NaturalGas', 'Gas', 'HeatPump', 'DistrictHeating', 'DistrictHeatingWater', 'DistrictHeatingSteam'
          heating_type = main_heat_fuel
          hot_water_loop = OpenstudioStandards::HVAC.model_get_or_add_hot_water_loop(model, main_heat_fuel,
                                                                                     hot_water_loop_type: hot_water_loop_type)
        when 'AirSourceHeatPump'
          heating_type = main_heat_fuel
          hot_water_loop = OpenstudioStandards::HVAC.model_get_or_add_hot_water_loop(model, main_heat_fuel,
                                                                                     hot_water_loop_type: 'LowTemperature')
        else
          heating_type = 'Electricity'
          hot_water_loop = nil
        end

        case air_loop_cooling_type
        when 'Water'
          chilled_water_loop = OpenstudioStandards::HVAC.model_get_or_add_chilled_water_loop(model, cool_fuel,
                                                                                             chilled_water_loop_cooling_type: chilled_water_loop_cooling_type)
        else
          chilled_water_loop = nil
        end

        if hot_water_loop.nil?
          case zone_heat_fuel
          when 'NaturalGas', 'Gas'
            reheat_type = 'NaturalGas'
          when 'Electricity'
            reheat_type = 'Electricity'
          else
            OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "zone_heat_fuel '#{zone_heat_fuel}' not supported with main_heat_fuel '#{main_heat_fuel}' for a 'VAV Reheat' system type.")
            return false
          end
        else
          reheat_type = 'Water'
        end

        OpenstudioStandards::HVAC.model_add_vav_reheat(model, zones,
                                                       heating_type: heating_type,
                                                       reheat_type: reheat_type,
                                                       hot_water_loop: hot_water_loop,
                                                       chilled_water_loop: chilled_water_loop,
                                                       fan_efficiency: 0.62,
                                                       fan_motor_efficiency: 0.9,
                                                       fan_pressure_rise: 4.0)

      when 'VAV No Reheat'
        case main_heat_fuel
        when 'NaturalGas', 'Gas', 'HeatPump', 'DistrictHeating', 'DistrictHeatingWater', 'DistrictHeatingSteam'
          heating_type = main_heat_fuel
          hot_water_loop = OpenstudioStandards::HVAC.model_get_or_add_hot_water_loop(model, main_heat_fuel,
                                                                                     hot_water_loop_type: hot_water_loop_type)
        when 'AirSourceHeatPump'
          heating_type = main_heat_fuel
          hot_water_loop = OpenstudioStandards::HVAC.model_get_or_add_hot_water_loop(model, main_heat_fuel,
                                                                                     hot_water_loop_type: 'LowTemperature')
        else
          heating_type = 'Electricity'
          hot_water_loop = nil
        end

        if air_loop_cooling_type == 'Water'
          chilled_water_loop = OpenstudioStandards::HVAC.model_get_or_add_chilled_water_loop(model, cool_fuel,
                                                                                             chilled_water_loop_cooling_type: chilled_water_loop_cooling_type)
        else
          chilled_water_loop = nil
        end
        OpenstudioStandards::HVAC.model_add_vav_reheat(model, zones,
                                                       heating_type: heating_type,
                                                       reheat_type: nil,
                                                       hot_water_loop: hot_water_loop,
                                                       chilled_water_loop: chilled_water_loop,
                                                       fan_efficiency: 0.62,
                                                       fan_motor_efficiency: 0.9,
                                                       fan_pressure_rise: 4.0)

      when 'VAV Gas Reheat'
        if air_loop_cooling_type == 'Water'
          chilled_water_loop = OpenstudioStandards::HVAC.model_get_or_add_chilled_water_loop(model, cool_fuel,
                                                                                             chilled_water_loop_cooling_type: chilled_water_loop_cooling_type)
        else
          chilled_water_loop = nil
        end
        OpenstudioStandards::HVAC.model_add_vav_reheat(model, zones,
                                                       heating_type: 'NaturalGas',
                                                       reheat_type: 'NaturalGas',
                                                       chilled_water_loop: chilled_water_loop,
                                                       fan_efficiency: 0.62,
                                                       fan_motor_efficiency: 0.9,
                                                       fan_pressure_rise: 4.0)

      when 'PVAV Reheat'
        case main_heat_fuel
        when 'AirSourceHeatPump'
          hot_water_loop = OpenstudioStandards::HVAC.model_get_or_add_hot_water_loop(model, main_heat_fuel,
                                                                                     hot_water_loop_type: 'LowTemperature')
        else
          if air_loop_heating_type == 'Water'
            hot_water_loop = OpenstudioStandards::HVAC.model_get_or_add_hot_water_loop(model, main_heat_fuel,
                                                                                       hot_water_loop_type: hot_water_loop_type)
          else
            heating_type = main_heat_fuel
          end
        end

        case cool_fuel
        when 'Electricity'
          chilled_water_loop = nil
        else
          chilled_water_loop = OpenstudioStandards::HVAC.model_get_or_add_chilled_water_loop(model, cool_fuel,
                                                                                             chilled_water_loop_cooling_type: chilled_water_loop_cooling_type)
        end

        if zone_heat_fuel == 'Electricity'
          electric_reheat = true
        else
          electric_reheat = false
        end

        OpenstudioStandards::HVAC.model_add_pvav(model, zones,
                                                 hot_water_loop: hot_water_loop,
                                                 chilled_water_loop: chilled_water_loop,
                                                 heating_type: heating_type,
                                                 electric_reheat: electric_reheat)

      when 'PVAV PFP Boxes'
        case cool_fuel
        when 'DistrictCooling'
          chilled_water_loop = OpenstudioStandards::HVAC.model_get_or_add_chilled_water_loop(model, cool_fuel)
        else
          chilled_water_loop = nil
        end
        OpenstudioStandards::HVAC.model_add_pvav_pfp_boxes(model, zones,
                                                           chilled_water_loop: chilled_water_loop,
                                                           fan_efficiency: 0.62,
                                                           fan_motor_efficiency: 0.9,
                                                           fan_pressure_rise: 4.0)

      when 'VAV PFP Boxes'
        chilled_water_loop = OpenstudioStandards::HVAC.model_get_or_add_chilled_water_loop(model, cool_fuel,
                                                                                           chilled_water_loop_cooling_type: chilled_water_loop_cooling_type)
        OpenstudioStandards::HVAC.model_add_pvav_pfp_boxes(model, zones,
                                                           chilled_water_loop: chilled_water_loop,
                                                           fan_efficiency: 0.62,
                                                           fan_motor_efficiency: 0.9,
                                                           fan_pressure_rise: 4.0)

      when 'Water Source Heat Pumps'
        if (main_heat_fuel.include?('DistrictHeating') && cool_fuel == 'DistrictCooling') || (main_heat_fuel == 'AmbientLoop' && cool_fuel == 'AmbientLoop')
          condenser_loop = OpenstudioStandards::HVAC.model_get_or_add_ambient_water_loop(model)
        else
          condenser_loop = OpenstudioStandards::HVAC.model_get_or_add_heat_pump_loop(model, main_heat_fuel, cool_fuel,
                                                                                     heat_pump_loop_cooling_type: heat_pump_loop_cooling_type)
        end
        OpenstudioStandards::HVAC.model_add_water_source_hp(model, zones,
                                                            condenser_loop,
                                                            ventilation: zone_equipment_ventilation)

      when 'Ground Source Heat Pumps'
        condenser_loop = OpenstudioStandards::HVAC.model_get_or_add_ground_hx_loop(model)
        OpenstudioStandards::HVAC.model_add_water_source_hp(model, zones,
                                                            condenser_loop,
                                                            ventilation: zone_equipment_ventilation)

      when 'DOAS Cold Supply'
        hot_water_loop = OpenstudioStandards::HVAC.model_get_or_add_hot_water_loop(model, main_heat_fuel,
                                                                                   hot_water_loop_type: hot_water_loop_type)
        chilled_water_loop = OpenstudioStandards::HVAC.model_get_or_add_chilled_water_loop(model, cool_fuel,
                                                                                           chilled_water_loop_cooling_type: chilled_water_loop_cooling_type)
        OpenstudioStandards::HVAC.model_add_doas_cold_supply(model, zones,
                                                             hot_water_loop: hot_water_loop,
                                                             chilled_water_loop: chilled_water_loop)

      when 'DOAS'
        if air_loop_heating_type == 'Water'
          case main_heat_fuel
          when nil
            hot_water_loop = nil
          when 'AirSourceHeatPump'
            hot_water_loop = OpenstudioStandards::HVAC.model_get_or_add_hot_water_loop(model, main_heat_fuel,
                                                                                       hot_water_loop_type: 'LowTemperature')
          when 'Electricity'
            OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "air_loop_heating_type '#{air_loop_heating_type}' is not supported with main_heat_fuel '#{main_heat_fuel}' for a 'DOAS' system type.")
            return false
          else
            hot_water_loop = OpenstudioStandards::HVAC.model_get_or_add_hot_water_loop(model, main_heat_fuel,
                                                                                       hot_water_loop_type: hot_water_loop_type)
          end
        else
          hot_water_loop = nil
        end
        if air_loop_cooling_type == 'Water'
          chilled_water_loop = OpenstudioStandards::HVAC.model_get_or_add_chilled_water_loop(model, cool_fuel,
                                                                                             chilled_water_loop_cooling_type: chilled_water_loop_cooling_type)
        else
          chilled_water_loop = nil
        end

        OpenstudioStandards::HVAC.model_add_doas(model, zones,
                                                 hot_water_loop: hot_water_loop,
                                                 chilled_water_loop: chilled_water_loop)

      when 'DOAS with DCV'
        if air_loop_heating_type == 'Water'
          case main_heat_fuel
          when nil
            hot_water_loop = nil
          when 'AirSourceHeatPump'
            hot_water_loop = OpenstudioStandards::HVAC.model_get_or_add_hot_water_loop(model, main_heat_fuel,
                                                                                       hot_water_loop_type: 'LowTemperature')
          else
            hot_water_loop = OpenstudioStandards::HVAC.model_get_or_add_hot_water_loop(model, main_heat_fuel,
                                                                                       hot_water_loop_type: hot_water_loop_type)
          end
        else
          hot_water_loop = nil
        end
        if air_loop_cooling_type == 'Water'
          chilled_water_loop = OpenstudioStandards::HVAC.model_get_or_add_chilled_water_loop(model, cool_fuel,
                                                                                             chilled_water_loop_cooling_type: chilled_water_loop_cooling_type)
        else
          chilled_water_loop = nil
        end

        OpenstudioStandards::HVAC.model_add_doas(model, zones,
                                                 hot_water_loop: hot_water_loop,
                                                 chilled_water_loop: chilled_water_loop,
                                                 doas_type: 'DOASVAV',
                                                 demand_control_ventilation: true)

      when 'DOAS with Economizing'
        if air_loop_heating_type == 'Water'
          case main_heat_fuel
          when nil
            hot_water_loop = nil
          when 'AirSourceHeatPump'
            hot_water_loop = OpenstudioStandards::HVAC.model_get_or_add_hot_water_loop(model, main_heat_fuel,
                                                                                       hot_water_loop_type: 'LowTemperature')
          else
            hot_water_loop = OpenstudioStandards::HVAC.model_get_or_add_hot_water_loop(model, main_heat_fuel,
                                                                                       hot_water_loop_type: hot_water_loop_type)
          end
        else
          hot_water_loop = nil
        end
        if air_loop_cooling_type == 'Water'
          chilled_water_loop = OpenstudioStandards::HVAC.model_get_or_add_chilled_water_loop(model, cool_fuel,
                                                                                             chilled_water_loop_cooling_type: chilled_water_loop_cooling_type)
        else
          chilled_water_loop = nil
        end

        OpenstudioStandards::HVAC.model_add_doas(model, zones,
                                                 hot_water_loop: hot_water_loop,
                                                 chilled_water_loop: chilled_water_loop,
                                                 doas_type: 'DOASVAV',
                                                 econo_ctrl_mthd: 'FixedDryBulb')

      when 'ERVs'
        OpenstudioStandards::HVAC.model_add_zone_erv(model, zones)

      when 'Residential ERVs'
        OpenstudioStandards::HVAC.model_add_residential_erv(model, zones)

      when 'Residential Ventilators'
        OpenstudioStandards::HVAC.model_add_residential_ventilator(model, zones)

      when 'Evaporative Cooler'
        OpenstudioStandards::HVAC.model_add_evap_cooler(model, zones)

      when 'Ideal Air Loads'
        OpenstudioStandards::HVAC.model_add_ideal_air_loads(model, zones)

      else
        # Combination Systems
        if system_type.include? 'with DOAS with DCV'
          # add DOAS DCV system
          OpenstudioStandards::HVAC.model_add_hvac_system(model, 'DOAS with DCV', main_heat_fuel, zone_heat_fuel, cool_fuel, zones,
                                                          hot_water_loop_type: hot_water_loop_type,
                                                          chilled_water_loop_cooling_type: chilled_water_loop_cooling_type,
                                                          heat_pump_loop_cooling_type: heat_pump_loop_cooling_type,
                                                          air_loop_heating_type: air_loop_heating_type,
                                                          air_loop_cooling_type: air_loop_cooling_type,
                                                          zone_equipment_ventilation: false,
                                                          fan_coil_capacity_control_method: fan_coil_capacity_control_method)
          # add paired system type
          paired_system_type = system_type.gsub(' with DOAS with DCV', '')
          OpenstudioStandards::HVAC.model_add_hvac_system(model, paired_system_type, main_heat_fuel, zone_heat_fuel, cool_fuel, zones,
                                                          hot_water_loop_type: hot_water_loop_type,
                                                          chilled_water_loop_cooling_type: chilled_water_loop_cooling_type,
                                                          heat_pump_loop_cooling_type: heat_pump_loop_cooling_type,
                                                          air_loop_heating_type: air_loop_heating_type,
                                                          air_loop_cooling_type: air_loop_cooling_type,
                                                          zone_equipment_ventilation: false,
                                                          fan_coil_capacity_control_method: fan_coil_capacity_control_method)
        elsif system_type.include? 'with DOAS'
          # add DOAS system
          OpenstudioStandards::HVAC.model_add_hvac_system(model, 'DOAS', main_heat_fuel, zone_heat_fuel, cool_fuel, zones,
                                                          hot_water_loop_type: hot_water_loop_type,
                                                          chilled_water_loop_cooling_type: chilled_water_loop_cooling_type,
                                                          heat_pump_loop_cooling_type: heat_pump_loop_cooling_type,
                                                          air_loop_heating_type: air_loop_heating_type,
                                                          air_loop_cooling_type: air_loop_cooling_type,
                                                          zone_equipment_ventilation: false,
                                                          fan_coil_capacity_control_method: fan_coil_capacity_control_method)
          # add paired system type
          paired_system_type = system_type.gsub(' with DOAS', '')
          OpenstudioStandards::HVAC.model_add_hvac_system(model, paired_system_type, main_heat_fuel, zone_heat_fuel, cool_fuel, zones,
                                                          hot_water_loop_type: hot_water_loop_type,
                                                          chilled_water_loop_cooling_type: chilled_water_loop_cooling_type,
                                                          heat_pump_loop_cooling_type: heat_pump_loop_cooling_type,
                                                          air_loop_heating_type: air_loop_heating_type,
                                                          air_loop_cooling_type: air_loop_cooling_type,
                                                          zone_equipment_ventilation: false,
                                                          fan_coil_capacity_control_method: fan_coil_capacity_control_method)
        elsif system_type.include? 'with ERVs'
          # add DOAS system
          OpenstudioStandards::HVAC.model_add_hvac_system(model, 'ERVs', main_heat_fuel, zone_heat_fuel, cool_fuel, zones,
                                                          hot_water_loop_type: hot_water_loop_type,
                                                          chilled_water_loop_cooling_type: chilled_water_loop_cooling_type,
                                                          heat_pump_loop_cooling_type: heat_pump_loop_cooling_type,
                                                          air_loop_heating_type: air_loop_heating_type,
                                                          air_loop_cooling_type: air_loop_cooling_type,
                                                          zone_equipment_ventilation: false,
                                                          fan_coil_capacity_control_method: fan_coil_capacity_control_method)
          # add paired system type
          paired_system_type = system_type.gsub(' with ERVs', '')
          OpenstudioStandards::HVAC.model_add_hvac_system(model, paired_system_type, main_heat_fuel, zone_heat_fuel, cool_fuel, zones,
                                                          hot_water_loop_type: hot_water_loop_type,
                                                          chilled_water_loop_cooling_type: chilled_water_loop_cooling_type,
                                                          heat_pump_loop_cooling_type: heat_pump_loop_cooling_type,
                                                          air_loop_heating_type: air_loop_heating_type,
                                                          air_loop_cooling_type: air_loop_cooling_type,
                                                          zone_equipment_ventilation: false,
                                                          fan_coil_capacity_control_method: fan_coil_capacity_control_method)
        else
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', "HVAC system type '#{system_type}' not recognized")
          return false
        end
      end

      # rename air loop and plant loop nodes for readability
      OpenstudioStandards::HVAC.rename_air_loop_nodes(model)
      OpenstudioStandards::HVAC.rename_plant_loop_nodes(model)
    end
  end
end
