module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Creator:Composers
    # Spec composers: thin translations of the legacy +model_add_*+ system-creator signatures into a
    # creator spec passed to {OpenstudioStandards::HVAC.apply_hvac}. A composer builds no OpenStudio
    # objects itself (beyond referenced schedules) — it assembles the declarative spec and returns the
    # handle the legacy method returned, so the factory becomes the single object-creation path.
    #
    # This is the Phase 11 conversion pattern. Each composer reproduces the legacy method's default
    # naming so downstream standards code that finds equipment by name keeps working.
    module Composers
      # Compose a hot water loop, equivalent to +model_add_hw_loop+.
      #
      # @param model [OpenStudio::Model::Model] the model
      # @param boiler_fuel_type [String] the boiler fuel type (or a district / heat-pump source)
      # @param ambient_loop [OpenStudio::Model::PlantLoop, nil] ambient loop for a heat-pump source
      # @param system_name [String] the loop name
      # @param dsgn_sup_wtr_temp [Double] design supply water temperature (F)
      # @param dsgn_sup_wtr_temp_delt [Double] design supply-return temperature difference (R)
      # @param pump_spd_ctrl [String] 'Variable' or 'Constant'
      # @param pump_tot_hd [Double, nil] pump rated head (ft H2O)
      # @param boiler_draft_type [String, nil] boiler draft type
      # @param boiler_eff_curve_temp_eval_var [String, nil] boiler efficiency curve evaluation variable
      # @param boiler_lvg_temp_dsgn [Double, nil] boiler design leaving temperature (F)
      # @param boiler_out_temp_lmt [Double, nil] boiler outlet temperature limit (F)
      # @param boiler_max_plr [Double, nil] boiler maximum part-load ratio
      # @param boiler_sizing_factor [Double, nil] boiler sizing factor
      # @return [OpenStudio::Model::PlantLoop] the hot water loop
      def self.hw_loop(model, boiler_fuel_type,
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
        name = system_name || 'Hot Water Loop'
        supply_temp_f = dsgn_sup_wtr_temp || 180.0
        supply_delta_r = dsgn_sup_wtr_temp_delt || 20.0

        # Pre-create the loop temperature schedule so the setpoint manager and its schedule carry the
        # conventional names (the factory references it by name).
        temp_schedule_name = "#{name} Temp - #{supply_temp_f.round(0)}F"
        OpenstudioStandards::Schedules.create_constant_schedule_ruleset(
          model, OpenStudio.convert(supply_temp_f, 'F', 'C').get,
          name: temp_schedule_name, schedule_type_limit: 'Temperature'
        )

        boiler_options = {
          draft_type: boiler_draft_type,
          eff_curve_temp_eval_var: boiler_eff_curve_temp_eval_var,
          lvg_temp: boiler_lvg_temp_dsgn,
          out_temp_lmt: boiler_out_temp_lmt,
          max_plr: boiler_max_plr,
          sizing_factor: boiler_sizing_factor
        }
        heat_source = heat_source_spec(model, name, boiler_fuel_type, supply_temp_f, ambient_loop, boiler_options)

        loop_spec = {
          name: name,
          design_info: { loop_type: 'Heating', supply_temp_f: supply_temp_f, temp_delta_r: supply_delta_r },
          min_loop_temp_c: 10.0,
          supply_inlet_components: [pump_spec(name, pump_spd_ctrl, pump_tot_hd)],
          supply_branches: [[heat_source]],
          controls: [{ spm_type: 'Scheduled', name: "#{name} Setpoint Manager", spm_sch_name: temp_schedule_name }]
        }

        context = OpenstudioStandards::HVAC.apply_hvac(model, { plant_loop_info: [loop_spec] })
        context.plant_loop(name)
      end

      # The pump component spec for a hot water loop.
      #
      # @param loop_name [String] the loop name
      # @param speed_control [String] 'Variable' or 'Constant'
      # @param total_head [Double, nil] rated head (ft H2O), defaulting to 60
      # @return [Hash] the pump spec
      def self.pump_spec(loop_name, speed_control, total_head)
        obj_type = speed_control == 'Constant' ? 'PumpConstantSpeed' : 'PumpVariableSpeed'
        {
          obj_type: obj_type,
          name: "#{loop_name} Pump",
          pump_head_fth2o: total_head || 60.0,
          motor_efficiency: 0.9,
          pump_ctrl_type: 'Intermittent'
        }
      end

      # The heating-source component spec for a hot water loop, selected by fuel type: a boiler, a
      # district heating source, an ambient-loop water-to-water heat pump, or a central air-source
      # heat pump.
      #
      # @param model [OpenStudio::Model::Model] the model (for the district-heating name era)
      # @param loop_name [String] the loop name
      # @param fuel_type [String] the fuel type
      # @param supply_temp_f [Double] the design supply water temperature (F)
      # @param ambient_loop [OpenStudio::Model::PlantLoop, nil] ambient loop for a heat-pump source
      # @return [Hash] the heating-source component spec
      def self.heat_source_spec(model, loop_name, fuel_type, supply_temp_f, ambient_loop, boiler_options = {})
        case fuel_type
        when 'DistrictHeating', 'DistrictHeatingWater', 'DistrictHeatingSteam'
          { obj_type: district_heating_type(model, fuel_type), name: "#{loop_name} District Heating", autosize: true }
        when 'HeatPump', 'AmbientLoop'
          # Reject heat to a get-or-added ambient loop; the factory connects the heat pump's source
          # side to that loop's demand side via condenser_loop_name.
          ambient = ambient_loop || OpenstudioStandards::HVAC.model_get_or_add_ambient_water_loop(model)
          { obj_type: 'HeatPumpWaterToWaterEquationFitHeating',
            name: "#{loop_name} Water to Water Heat Pump",
            condenser_loop_name: ambient.name.get }
        when 'AirSourceHeatPump', 'ASHP'
          # No name key: the shared creator applies an EMS-friendly name derived from the loop, which
          # the EMS program references. plant_loop_name lets the self-placing component find its loop.
          { obj_type: 'AirSourceHeatPump', plant_loop_name: loop_name }
        else
          boiler_spec(loop_name, fuel_type, supply_temp_f, boiler_options)
        end
      end

      # The boiler component spec, reproducing the legacy model_add_hw_loop boiler defaults.
      #
      # @param loop_name [String] the loop name
      # @param fuel_type [String] the boiler fuel type
      # @param supply_temp_f [Double] the design supply water temperature (F)
      # @param options [Hash] boiler overrides (draft_type, eff_curve_temp_eval_var, lvg_temp, out_temp_lmt, max_plr, sizing_factor)
      # @return [Hash] the boiler spec
      def self.boiler_spec(loop_name, fuel_type, supply_temp_f, options)
        # No name key: the shared boiler creator defaults an unnamed boiler to "Boiler", matching
        # the legacy hot water loop.
        spec = {
          obj_type: 'BoilerHotWater',
          fuel_type: fuel_type,
          eff: 0.78,
          leaving_temp_design_f: options[:lvg_temp] || supply_temp_f,
          outlet_temp_limit_f: options[:out_temp_lmt] || 203.0
        }
        spec[:draft_type] = options[:draft_type] if options[:draft_type]
        spec[:eff_curve_temp_eval_var] = options[:eff_curve_temp_eval_var] if options[:eff_curve_temp_eval_var]
        spec[:max_plr] = options[:max_plr] if options[:max_plr]
        spec[:sizing_factor] = options[:sizing_factor] if options[:sizing_factor]
        spec
      end

      # Compose a chilled water loop, equivalent to +model_add_chw_loop+.
      #
      # Supports the 'constant primary' and 'constant primary variable secondary common pipe' pumping
      # configurations; the 'constant primary variable secondary heat exchanger' configuration (which
      # builds a renamed primary/secondary loop pair with multi-chiller EMS) is not yet convertible
      # and raises.
      #
      # @param model [OpenStudio::Model::Model] the model
      # @param system_name [String] the loop name
      # @param cooling_fuel [String] 'Electricity' (chillers) or 'DistrictCooling'
      # @param dsgn_sup_wtr_temp [Double] design supply water temperature (F)
      # @param dsgn_sup_wtr_temp_delt [Double] design supply-return temperature difference (R)
      # @param chw_pumping_configuration [String] the pumping configuration
      # @param chiller_cooling_type [String, nil] 'AirCooled' or 'WaterCooled'
      # @param chiller_condenser_type [String, nil] chiller condenser type (used in the chiller name)
      # @param chiller_compressor_type [String, nil] chiller compressor type (used in the chiller name)
      # @param num_chillers [Integer] the number of chillers
      # @param condenser_water_loop [OpenStudio::Model::PlantLoop, nil] condenser loop for water-cooled chillers
      # @param waterside_economizer [String] 'none', 'integrated', or 'non-integrated'
      # @param outdoor_air_reset [Boolean] apply outdoor air temperature reset to the supply water setpoint
      # @return [OpenStudio::Model::PlantLoop] the chilled water loop
      def self.chw_loop(model,
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
        if chw_pumping_configuration == 'constant primary variable secondary heat exchanger'
          raise NotImplementedError, "chw_loop composer does not yet support the '#{chw_pumping_configuration}' pumping configuration"
        end

        name = system_name || 'Chilled Water Loop'
        supply_temp_f = dsgn_sup_wtr_temp || 44.0
        supply_delta_r = dsgn_sup_wtr_temp_delt || 10.1

        loop_spec = {
          name: name,
          design_info: { loop_type: 'Cooling', supply_temp_f: supply_temp_f, temp_delta_r: supply_delta_r },
          min_loop_temp_f: 34.0,
          max_loop_temp_f: 104.0,
          supply_bypass_name: "#{name} Chiller Bypass",
          supply_branches: cooling_source_branches(name, cooling_fuel, supply_temp_f, num_chillers, condenser_water_loop,
                                                    chiller_cooling_type, chiller_condenser_type, chiller_compressor_type),
          controls: [chw_control_spec(model, name, supply_temp_f, outdoor_air_reset)]
        }
        add_chw_pumps(loop_spec, name, chw_pumping_configuration)
        add_waterside_economizer(loop_spec, condenser_water_loop, waterside_economizer)

        context = OpenstudioStandards::HVAC.apply_hvac(model, { plant_loop_info: [loop_spec] })
        context.plant_loop(name)
      end

      # The cooling-source supply branches: one district cooling branch, or one branch per chiller.
      #
      # @return [Array<Array<Hash>>] the supply branches
      def self.cooling_source_branches(loop_name, cooling_fuel, supply_temp_f, num_chillers, condenser_loop,
                                       cooling_type, condenser_type, compressor_type)
        return [[{ obj_type: 'DistrictCooling', name: 'Purchased Cooling', autosize: true }]] if cooling_fuel == 'DistrictCooling'

        default_cop = cooling_type == 'AirCooled' ? OpenstudioStandards::HVAC.kw_per_ton_to_cop(1.188) : OpenstudioStandards::HVAC.kw_per_ton_to_cop(0.66)
        sizing_factor = (1.0 / num_chillers).round(2)
        (0...num_chillers).map do |index|
          chiller = {
            obj_type: 'ChillerElectricEIR',
            name: "#{cooling_type} #{condenser_type} #{compressor_type} Chiller #{index}",
            cop: default_cop,
            leaving_chw_temp_f: supply_temp_f,
            leaving_chw_lower_limit_f: 36.0,
            entering_cw_temp_f: 95.0,
            min_plr: 0.15,
            max_plr: 1.0,
            opt_plr: 1.0,
            min_unloading_ratio: 0.25,
            flow_mode: 'ConstantFlow',
            sizing_factor: sizing_factor
          }
          chiller[:condenser_loop_name] = condenser_loop.name.get if condenser_loop
          [chiller]
        end
      end

      # The loop setpoint manager spec: an outdoor-air reset, or a scheduled constant setpoint (whose
      # schedule is pre-created with the conventional name).
      #
      # @return [Hash] the setpoint manager spec
      def self.chw_control_spec(model, loop_name, supply_temp_f, outdoor_air_reset)
        if outdoor_air_reset
          return {
            spm_type: 'OutdoorAirReset', name: "#{loop_name} Setpoint Manager",
            oat_high_f: 80.0, setpoint_at_oat_high_f: 44.0, oat_low_f: 60.0, setpoint_at_oat_low_f: 54.0
          }
        end

        schedule_name = "#{loop_name} Temp - #{supply_temp_f.round(0)}F"
        OpenstudioStandards::Schedules.create_constant_schedule_ruleset(
          model, OpenStudio.convert(supply_temp_f, 'F', 'C').get,
          name: schedule_name, schedule_type_limit: 'Temperature'
        )
        { spm_type: 'Scheduled', name: "#{loop_name} Setpoint Manager", spm_sch_name: schedule_name }
      end

      # Add the chilled water pumps for a pumping configuration.
      #
      # @return [void]
      def self.add_chw_pumps(loop_spec, loop_name, configuration)
        case configuration
        when 'constant primary'
          loop_spec[:supply_inlet_components] = [
            { obj_type: 'PumpVariableSpeed', name: "#{loop_name} Pump", pump_head_fth2o: 60.0, motor_efficiency: 0.9,
              frac_motor_to_fluid: 0, plr_coeffs: [0, 1, 0, 0], pump_ctrl_type: 'Intermittent' }
          ]
        when 'constant primary variable secondary common pipe'
          loop_spec[:supply_inlet_components] = [
            { obj_type: 'PumpConstantSpeed', name: "#{loop_name} Primary Pump", pump_head_fth2o: 15.0,
              motor_efficiency: 0.9, pump_ctrl_type: 'Intermittent' }
          ]
          loop_spec[:demand_inlet_components] = [
            { obj_type: 'PumpVariableSpeed', name: "#{loop_name} Secondary Pump", pump_head_fth2o: 45.0, motor_efficiency: 0.9,
              frac_motor_to_fluid: 0, plr_coeffs: [0, 0.0205, 0.4101, 0.5753], pump_ctrl_type: 'Intermittent' }
          ]
          loop_spec[:common_pipe_sim] = 'CommonPipe'
        else
          raise ArgumentError, "chw_loop composer requires a supported chw_pumping_configuration; got #{configuration.inspect}"
        end
        nil
      end

      # Declare a waterside economizer on the loop spec when a condenser loop and mode are given.
      #
      # @return [void]
      def self.add_waterside_economizer(loop_spec, condenser_loop, mode)
        return if condenser_loop.nil?
        return unless %w[integrated non-integrated].include?(mode)

        loop_spec[:waterside_economizer] = { condenser_loop_name: condenser_loop.name.get, integrated: mode == 'integrated' }
        nil
      end

      # Compose a condenser water loop, equivalent to +model_add_cw_loop+.
      #
      # Covers the declarative configuration: sizing, the follow-outdoor-air-wetbulb setpoint manager,
      # every pump speed-control type, and the single-speed (fluid-bypass / fan-cycling) and two-speed
      # cooling towers. The 90.1 design-sizing methodology (+use_90_1_design_sizing: true+, the default)
      # recomputes the loop sizing from the model design days at runtime and is not declaratively
      # expressible; it raises. The variable-speed tower (which builds a custom fan-power curve) also
      # raises.
      #
      # @param model [OpenStudio::Model::Model] the model
      # @param system_name [String] the loop name
      # @param cooling_tower_type [String] cooling tower type (used in the tower name)
      # @param cooling_tower_fan_type [String] cooling tower fan type (used in the tower name)
      # @param cooling_tower_capacity_control [String] capacity control (selects the tower object)
      # @param number_of_cells_per_tower [Integer] cells per tower
      # @param number_cooling_towers [Integer] number of towers (in parallel)
      # @param use_90_1_design_sizing [Boolean] apply the 90.1 approach-temperature sizing (unsupported)
      # @param sup_wtr_temp [Double] supply water temperature (F)
      # @param dsgn_sup_wtr_temp [Double] design supply water temperature (F)
      # @param dsgn_sup_wtr_temp_delt [Double] design range temperature (R)
      # @param wet_bulb_approach [Double] design wet-bulb approach (R)
      # @param pump_spd_ctrl [String] pump speed control ('Constant', 'Variable', 'HeaderedVariable', 'HeaderedConstant')
      # @param pump_tot_hd [Double] pump head (ft H2O)
      # @return [OpenStudio::Model::PlantLoop] the condenser water loop
      def self.cw_loop(model,
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
        if use_90_1_design_sizing
          raise NotImplementedError, 'cw_loop composer does not yet support use_90_1_design_sizing (the 90.1 approach-temperature sizing recomputes from design days at runtime); pass use_90_1_design_sizing: false'
        end
        if cooling_tower_capacity_control == 'Variable Speed Fan'
          raise NotImplementedError, "cw_loop composer does not yet support the '#{cooling_tower_capacity_control}' cooling tower (it builds a custom fan-power curve)"
        end

        name = system_name || 'Condenser Water Loop'
        sup_wtr_temp ||= 70.0
        dsgn_sup_wtr_temp ||= 85.0
        dsgn_sup_wtr_temp_delt ||= 10.0
        wet_bulb_approach ||= 7.0

        loop_spec = {
          name: name,
          design_info: {
            loop_type: 'Condenser', supply_temp_f: dsgn_sup_wtr_temp, temp_delta_r: dsgn_sup_wtr_temp_delt,
            sizing_option: 'Coincident', averaging_window: 6, coincident_sizing_factor_mode: 'GlobalCoolingSizingFactor'
          },
          min_loop_temp_c: 5.0,
          max_loop_temp_c: 80.0,
          supply_bypass_name: "#{name} Cooling Tower Bypass",
          demand_bypass_name: "#{name} Chiller Bypass",
          supply_inlet_components: [cw_pump_spec(name, pump_spd_ctrl, pump_tot_hd)],
          supply_branches: cooling_tower_branches(name, cooling_tower_type, cooling_tower_fan_type,
                                                  cooling_tower_capacity_control, number_of_cells_per_tower, number_cooling_towers),
          controls: [{
            spm_type: 'FollowOutdoorAir',
            name: "#{name} Setpoint Manager Follow OATwb with #{wet_bulb_approach}F Approach",
            ref_temp: 'OutdoorAirWetBulb',
            offset_temp_r: wet_bulb_approach,
            max_setpt_f: dsgn_sup_wtr_temp,
            min_setpt_f: sup_wtr_temp
          }]
        }

        context = OpenstudioStandards::HVAC.apply_hvac(model, { plant_loop_info: [loop_spec] })
        context.plant_loop(name)
      end

      # The condenser water pump spec for a pump speed-control type.
      #
      # @return [Hash] the pump spec
      def self.cw_pump_spec(loop_name, speed_control, total_head)
        obj_type = case speed_control
                   when 'Variable' then 'PumpVariableSpeed'
                   when 'HeaderedVariable' then 'HeaderedPumpsVariableSpeed'
                   when 'HeaderedConstant' then 'HeaderedPumpsConstantSpeed'
                   else 'PumpConstantSpeed'
                   end
        spec = { obj_type: obj_type, name: "#{loop_name} #{speed_control} Pump", pump_head_fth2o: total_head, pump_ctrl_type: 'Intermittent' }
        spec[:num_pumps] = 2 if %w[HeaderedVariable HeaderedConstant].include?(speed_control)
        spec
      end

      # The cooling-tower supply branches (one branch per tower).
      #
      # @return [Array<Array<Hash>>] the supply branches
      def self.cooling_tower_branches(loop_name, tower_type, fan_type, capacity_control, cells_per_tower, number_of_towers)
        obj_type, cell_control = case capacity_control
                                 when 'Fluid Bypass' then ['CoolingTowerSingleSpeed', 'FluidBypass']
                                 when 'Fan Cycling' then ['CoolingTowerSingleSpeed', 'FanCycling']
                                 when 'TwoSpeed Fan' then ['CoolingTowerTwoSpeed', nil]
                                 else raise ArgumentError, "cw_loop composer does not support cooling tower capacity control '#{capacity_control}'"
                                 end
        # Integer division mirrors the legacy sizing factor (0 for more than one tower).
        sizing_factor = 1 / number_of_towers
        Array.new(number_of_towers) do
          tower = {
            obj_type: obj_type,
            name: "#{fan_type} #{capacity_control} #{tower_type}",
            sizing_factor: sizing_factor,
            num_cells: cells_per_tower
          }
          tower[:cell_control] = cell_control if cell_control
          [tower]
        end
      end

      # Compose a heat pump (condenser) loop, equivalent to +model_add_hp_loop+.
      #
      # A dual-setpoint loop with a constant pump, a cooling source, and a heating source, each source
      # carrying a scheduled dual-setpoint manager on its outlet (all three managers share the loop
      # high/low temperature schedules). Cooling supports district cooling, single/two-speed cooling
      # towers, and single/two-speed evaporative fluid coolers; heating supports district heating, a
      # supplemental boiler, and a central air-source heat pump. The plain (dry) fluid coolers (which
      # autosize extra fields) and the variable-speed cooling tower are not yet convertible and raise.
      #
      # @param model [OpenStudio::Model::Model] the model
      # @param heating_fuel [String] heating source fuel/type
      # @param cooling_fuel [String] 'Electricity' or 'DistrictCooling'
      # @param cooling_type [String] cooling equipment type when not district cooling
      # @param system_name [String] the loop name
      # @param sup_wtr_high_temp [Double] high setpoint temperature (F)
      # @param sup_wtr_low_temp [Double] low setpoint temperature (F)
      # @param dsgn_sup_wtr_temp [Double] design supply water temperature (F)
      # @param dsgn_sup_wtr_temp_delt [Double] design supply-return temperature difference (R)
      # @return [OpenStudio::Model::PlantLoop] the heat pump loop
      def self.hp_loop(model,
                       heating_fuel: 'NaturalGas',
                       cooling_fuel: 'Electricity',
                       cooling_type: 'EvaporativeFluidCooler',
                       system_name: 'Heat Pump Loop',
                       sup_wtr_high_temp: 87.0,
                       sup_wtr_low_temp: 67.0,
                       dsgn_sup_wtr_temp: 102.2,
                       dsgn_sup_wtr_temp_delt: 19.8)
        name = system_name || 'Heat Pump Loop'
        high_temp_f = sup_wtr_high_temp || 87.0
        low_temp_f = sup_wtr_low_temp || 67.0
        design_temp_f = dsgn_sup_wtr_temp || 102.2
        design_delta_r = dsgn_sup_wtr_temp_delt || 19.8

        # Pre-create the shared high/low setpoint schedules referenced by all three dual-setpoint managers.
        high_sch = "#{name} High Temp - #{high_temp_f.round(0)}F"
        low_sch = "#{name} Low Temp - #{low_temp_f.round(0)}F"
        OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model, OpenStudio.convert(high_temp_f, 'F', 'C').get, name: high_sch, schedule_type_limit: 'Temperature')
        OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model, OpenStudio.convert(low_temp_f, 'F', 'C').get, name: low_sch, schedule_type_limit: 'Temperature')

        cooling_spec, cooling_spm_name, cooling_spm_node = hp_cooling_equipment(name, cooling_fuel, cooling_type)
        heating_spec, heating_spm_name, heating_spm_node = hp_heating_equipment(model, name, heating_fuel)

        loop_spec = {
          name: name,
          load_distribution_scheme: 'SequentialLoad',
          design_info: { loop_type: 'Heating', supply_temp_f: design_temp_f, temp_delta_r: design_delta_r },
          min_loop_temp_c: 10.0,
          max_loop_temp_c: 35.0,
          supply_bypass_name: "#{name} Supply Bypass",
          demand_bypass_name: "#{name} Demand Bypass",
          supply_inlet_components: [{ obj_type: 'PumpConstantSpeed', name: "#{name} Pump", pump_head_fth2o: 60.0, pump_ctrl_type: 'Intermittent' }],
          supply_branches: [[cooling_spec], [heating_spec]],
          controls: [
            { spm_type: 'ScheduledDual', name: "#{name} Scheduled Dual Setpoint", spm_hi_sch_name: high_sch, spm_lo_sch_name: low_sch },
            { spm_type: 'ScheduledDual', name: cooling_spm_name, spm_hi_sch_name: high_sch, spm_lo_sch_name: low_sch, spm_node: cooling_spm_node },
            { spm_type: 'ScheduledDual', name: heating_spm_name, spm_hi_sch_name: high_sch, spm_lo_sch_name: low_sch, spm_node: heating_spm_node }
          ]
        }

        context = OpenstudioStandards::HVAC.apply_hvac(model, { plant_loop_info: [loop_spec] })
        context.plant_loop(name)
      end

      # The cooling-source spec, its dual-setpoint manager name, and the component name its manager
      # is placed after.
      #
      # @return [Array(Hash, String, String)] the equipment spec, the setpoint manager name, and the spm_node
      def self.hp_cooling_equipment(loop_name, cooling_fuel, cooling_type)
        return [{ obj_type: 'DistrictCooling', name: "#{loop_name} District Cooling", autosize: true },
                "#{loop_name} District Cooling Scheduled Dual Setpoint", "#{loop_name} District Cooling"] if cooling_fuel == 'DistrictCooling'

        case cooling_type
        when 'CoolingTower', 'CoolingTowerTwoSpeed'
          equipment_name = "#{loop_name} CoolingTowerTwoSpeed"
          [{ obj_type: 'CoolingTowerTwoSpeed', name: equipment_name }, "#{loop_name} Cooling Tower Scheduled Dual Setpoint", equipment_name]
        when 'CoolingTowerSingleSpeed'
          equipment_name = "#{loop_name} CoolingTowerSingleSpeed"
          [{ obj_type: 'CoolingTowerSingleSpeed', name: equipment_name }, "#{loop_name} Cooling Tower Scheduled Dual Setpoint", equipment_name]
        when 'EvaporativeFluidCooler', 'EvaporativeFluidCoolerSingleSpeed'
          evap_fluid_cooler(loop_name, 'EvaporativeFluidCoolerSingleSpeed')
        when 'EvaporativeFluidCoolerTwoSpeed'
          evap_fluid_cooler(loop_name, 'EvaporativeFluidCoolerTwoSpeed')
        else
          raise NotImplementedError, "hp_loop composer does not yet support the '#{cooling_type}' cooling type"
        end
      end

      # An evaporative fluid cooler cooling-source spec (with the legacy spray water flow and
      # performance input method), its manager name, and its spm_node.
      #
      # @return [Array(Hash, String, String)] the equipment spec, the setpoint manager name, and the spm_node
      def self.evap_fluid_cooler(loop_name, obj_type)
        equipment_name = "#{loop_name} #{obj_type}"
        spec = {
          obj_type: obj_type,
          name: equipment_name,
          spray_water_flow_m3s: 0.002208,
          performance_input_method: 'UFactorTimesAreaAndDesignWaterFlowRate'
        }
        [spec, "#{loop_name} Fluid Cooler Scheduled Dual Setpoint", equipment_name]
      end

      # The heating-source spec, its dual-setpoint manager name, and the component name its manager
      # is placed after.
      #
      # @return [Array(Hash, String, String)] the equipment spec, the setpoint manager name, and the spm_node
      def self.hp_heating_equipment(model, loop_name, heating_fuel)
        case heating_fuel
        when 'DistrictHeating', 'DistrictHeatingWater', 'DistrictHeatingSteam'
          equipment_name = "#{loop_name} District Heating"
          [{ obj_type: district_heating_type(model, heating_fuel), name: equipment_name, autosize: true },
           "#{loop_name} District Heating Scheduled Dual Setpoint", equipment_name]
        when 'AirSourceHeatPump', 'ASHP'
          # The air-source heat pump is an EMS PlantComponentUserDefined proxy; its outlet node is not
          # reachable by the spm_node resolver (which handles straight and water-to-water components),
          # so the heating dual-setpoint manager cannot yet be placed on it.
          raise NotImplementedError, 'hp_loop composer does not yet support an AirSourceHeatPump heating source (its setpoint manager cannot be placed on the EMS proxy outlet)'
        else
          equipment_name = "#{loop_name} Supplemental Boiler"
          spec = {
            obj_type: 'BoilerHotWater', name: equipment_name, fuel_type: heating_fuel,
            flow_mode: 'ConstantFlow', leaving_temp_design_f: 86.0, min_plr: 0.0, max_plr: 1.2, opt_plr: 1.0
          }
          [spec, "#{loop_name} Boiler Scheduled Dual Setpoint", equipment_name]
        end
      end

      # Compose packaged single-zone air conditioners (one air loop per zone), equivalent to
      # +model_add_psz_ac+.
      #
      # Covers the packaged-AC configuration: a single-speed DX cooling coil (PSZ-AC curve set), a
      # gas / electric / no-heat main heating coil and electric / gas / no-heat supplemental coil, a
      # constant-volume or cycling on/off fan, a draw- or blow-through unitary system, an outdoor air
      # system, a single-zone-reheat setpoint manager, and an uncontrolled diffuser per zone. Water
      # coils and the heat-pump cooling/heating types (which add unitary heat-pump control logic) are
      # not yet convertible and raise.
      #
      # @param model [OpenStudio::Model::Model] the model
      # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] the zones to serve
      # @param system_name [String, nil] the system name suffix (defaults to "PSZ-AC")
      # @param cooling_type [String] cooling coil type
      # @param heating_type [String, nil] main heating coil type
      # @param supplemental_heating_type [String, nil] supplemental heating coil type
      # @param fan_location [String] 'DrawThrough' or 'BlowThrough'
      # @param fan_type [String] 'ConstantVolume' or 'Cycling'
      # @param hvac_op_sch [OpenStudio::Model::Schedule, nil] HVAC operating schedule (defaults to always on)
      # @param oa_damper_sch [OpenStudio::Model::Schedule, nil] OA damper schedule (defaults to always on)
      # @param econ_max_oa_frac_sch [OpenStudio::Model::Schedule, nil] economizer maximum OA fraction schedule
      # @return [Array<OpenStudio::Model::AirLoopHVAC>] the created air loops
      def self.psz_ac(model, thermal_zones,
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
        raise NotImplementedError, "psz_ac composer does not yet support the '#{cooling_type}' cooling type" unless ['Single Speed DX AC', 'Water'].include?(cooling_type)
        raise NotImplementedError, "psz_ac composer does not yet support the '#{heating_type}' heating type" if ['Single Speed Heat Pump', 'Water To Air Heat Pump'].include?(heating_type)
        raise ArgumentError, 'psz_ac water cooling requires a chilled water loop' if cooling_type == 'Water' && chilled_water_loop.nil?
        raise ArgumentError, 'psz_ac water heating requires a hot water loop' if heating_type == 'Water' && hot_water_loop.nil?

        op_sch = hvac_op_sch ? hvac_op_sch.name.get : 'AlwaysOn'
        oa_sch = oa_damper_sch ? oa_damper_sch.name.get : 'AlwaysOn'
        fan_preset = fan_type == 'Cycling' ? 'Packaged_RTU_SZ_AC_Cycling_Fan' : 'Packaged_RTU_SZ_AC_CAV_OnOff_Fan'
        fan_op_sch = fan_type == 'Cycling' ? 'AlwaysOff' : op_sch

        air_specs = []
        zone_specs = []
        thermal_zones.each do |zone|
          loop_name = system_name.nil? ? "#{zone.name} PSZ-AC" : "#{zone.name} #{system_name}"
          unitary = psz_unitary_spec(loop_name, op_sch, fan_preset, fan_op_sch, fan_location, heating_type,
                                     supplemental_heating_type, cooling_type, hot_water_loop, chilled_water_loop)
          air_specs << psz_air_spec(loop_name, zone.name.to_s, op_sch, oa_sch, econ_max_oa_frac_sch, unitary)
          zone_specs << psz_zone_spec(loop_name, zone.name.to_s)
        end

        context = OpenstudioStandards::HVAC.apply_hvac(model, { air_system_info: air_specs, zone_info: zone_specs })
        air_specs.map { |spec| context.air_loop(spec[:name]) }
      end

      # The per-zone air-system spec for a PSZ-AC.
      #
      # @return [Hash] the air_system_info entry
      def self.psz_air_spec(loop_name, zone_name, op_sch, oa_sch, econ_max_oa_frac_sch, unitary)
        economizer = { reset_min_db: true }
        economizer[:max_oa_frac_sch_name] = econ_max_oa_frac_sch.name.get if econ_max_oa_frac_sch
        {
          name: loop_name,
          design_info: { use_standard_sizing: true, des_heat_sat_f: 122.0, min_sys_airflow_ratio: 1.0 },
          availability: { schedule_name: op_sch, night_cycle: { control_type: 'CycleOnAny', run_time_s: 1800 } },
          oa_control: { ventilation: { min_oa_sch_name: oa_sch }, economizer: economizer },
          supply_components: [unitary],
          controls: [{ spm_type: 'SingleZoneReheat', name: "#{zone_name} Setpoint Manager SZ Reheat",
                       control_zone_name: zone_name, min_setpt_f: 55.0, max_setpt_f: 122.0 }]
        }
      end

      # The unitary system spec inside a PSZ-AC air loop.
      #
      # @return [Hash] the AirLoopHVACUnitarySystem component spec
      def self.psz_unitary_spec(loop_name, op_sch, fan_preset, fan_op_sch, fan_location, heating_type,
                                supplemental_heating_type, cooling_type, hot_water_loop, chilled_water_loop)
        {
          obj_type: 'AirLoopHVACUnitarySystem',
          name: "#{loop_name} Unitary AC",
          schedule_name: op_sch,
          fan_operation: { placement: fan_location, op_mode_sch_name: fan_op_sch },
          components: [
            { obj_type: 'FanOnOff', name: "#{loop_name} Fan", preset: fan_preset },
            psz_cooling_coil(loop_name, cooling_type, chilled_water_loop),
            psz_heating_coil(loop_name, heating_type, hot_water_loop: hot_water_loop, water_eat_f: 45.0, water_lat_f: 122.0),
            psz_supplemental_coil(loop_name, supplemental_heating_type)
          ]
        }
      end

      # The cooling coil spec for a PSZ-AC: a chilled-water coil, or the single-speed DX (PSZ-AC) coil.
      #
      # @return [Hash] the cooling coil component spec
      def self.psz_cooling_coil(loop_name, cooling_type, chilled_water_loop)
        if cooling_type == 'Water'
          { obj_type: 'CoilCoolingWater', name: "#{loop_name} Water Clg Coil", plant_loop_name: chilled_water_loop.name.get }
        else
          { obj_type: 'CoilCoolingDXSingleSpeed', name: "#{loop_name} 1spd DX AC Clg Coil", preset: 'PSZ-AC' }
        end
      end

      # The main heating coil spec for a packaged system (gas, electric, hot water, or no-heat). For
      # hot water, the rated air temperatures are optional (psz_ac passes them; psz_vav uses defaults).
      #
      # @return [Hash] the heating coil component spec
      def self.psz_heating_coil(loop_name, heating_type, hot_water_loop: nil, water_eat_f: nil, water_lat_f: nil)
        case heating_type
        when 'NaturalGas', 'Gas'
          { obj_type: 'CoilHeatingGas', name: "#{loop_name} Gas Htg Coil" }
        when 'Electricity', 'Electric'
          { obj_type: 'CoilHeatingElectric', name: "#{loop_name} Electric Htg Coil" }
        when 'Water'
          water_heating_coil("#{loop_name} Water Htg Coil", hot_water_loop, eat_f: water_eat_f, lat_f: water_lat_f)
        else
          { obj_type: 'CoilHeatingElectric', name: "#{loop_name} No Heat", schedule_name: 'AlwaysOff', capacity_w: 0.0 }
        end
      end

      # The supplemental heating coil spec for a PSZ-AC (assigned as the supplemental role).
      #
      # @return [Hash] the supplemental heating coil component spec
      def self.psz_supplemental_coil(loop_name, supplemental_heating_type)
        case supplemental_heating_type
        when 'Electricity', 'Electric'
          { obj_type: 'CoilHeatingElectric', name: "#{loop_name} Electric Backup Htg Coil", role: 'supplemental' }
        when 'NaturalGas', 'Gas'
          { obj_type: 'CoilHeatingGas', name: "#{loop_name} Gas Backup Htg Coil", role: 'supplemental' }
        else
          { obj_type: 'CoilHeatingElectric', name: "#{loop_name} No Heat", schedule_name: 'AlwaysOff', capacity_w: 0.0, role: 'supplemental' }
        end
      end

      # The per-zone zone-info spec for a PSZ-AC (uncontrolled diffuser + zone sizing).
      #
      # @return [Hash] the zone_info entry
      def self.psz_zone_spec(loop_name, zone_name)
        {
          zone_name: zone_name,
          air_loop_name: loop_name,
          air_terminal_info: { air_terminal_type: 'AirTerminalSingleDuctConstantVolumeNoReheat', name: "#{loop_name} Diffuser" },
          zone_sizing: { htg_max_airflow_fraction: 1.0, clg_dsgn_sup_air_temp_f: 55.0, htg_dsgn_sup_air_temp_f: 122.0 }
        }
      end

      # Compose packaged single-zone VAV systems (one air loop per zone), equivalent to
      # +model_add_psz_vav+.
      #
      # Covers the air-cooled configuration: a variable-speed DX cooling coil, a gas / electric /
      # no-heat main heating coil and electric / gas / no-backup supplemental coil, a variable-volume
      # fan, a SingleZoneVAV blow-through unitary system, an outdoor air system with heat-recovery
      # bypass, a single-zone-reheat setpoint manager, and a VAV no-reheat terminal per zone. Water
      # coils (WaterCooled cooling / Water heating) are not yet convertible and raise.
      #
      # @param model [OpenStudio::Model::Model] the model
      # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] the zones to serve
      # @param system_name [String, nil] the system name suffix (defaults to "PSZ-VAV")
      # @param heating_type [String, nil] main heating coil type
      # @param cooling_type [String] 'AirCooled' (variable-speed DX) or 'WaterCooled'
      # @param supplemental_heating_type [String, nil] supplemental heating coil type
      # @param hvac_op_sch [OpenStudio::Model::Schedule, nil] HVAC operating schedule (defaults to always on)
      # @param fan_type [String] typical-fan preset key for the variable-volume fan
      # @param oa_damper_sch [OpenStudio::Model::Schedule, nil] OA damper schedule (defaults to always on)
      # @param econ_max_oa_frac_sch [OpenStudio::Model::Schedule, nil] economizer maximum OA fraction schedule
      # @return [Array<OpenStudio::Model::AirLoopHVAC>] the created air loops
      def self.psz_vav(model, thermal_zones,
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
        raise NotImplementedError, "psz_vav composer does not yet support the '#{cooling_type}' cooling type" unless ['AirCooled', 'WaterCooled'].include?(cooling_type)
        raise ArgumentError, 'psz_vav water cooling requires a chilled water loop' if cooling_type == 'WaterCooled' && chilled_water_loop.nil?
        raise ArgumentError, 'psz_vav water heating requires a hot water loop' if heating_type == 'Water' && hot_water_loop.nil?

        op_sch = hvac_op_sch ? hvac_op_sch.name.get : 'AlwaysOn'
        oa_sch = oa_damper_sch ? oa_damper_sch.name.get : 'AlwaysOn'

        air_specs = []
        zone_specs = []
        thermal_zones.each do |zone|
          loop_name = system_name.nil? ? "#{zone.name} PSZ-VAV" : "#{zone.name} #{system_name}"
          unitary = psz_vav_unitary_spec(loop_name, zone.name.to_s, op_sch, fan_type, heating_type,
                                         supplemental_heating_type, cooling_type, hot_water_loop, chilled_water_loop)
          air_specs << psz_vav_air_spec(loop_name, zone.name.to_s, op_sch, oa_sch, econ_max_oa_frac_sch, unitary)
          zone_specs << {
            zone_name: zone.name.to_s,
            air_loop_name: loop_name,
            air_terminal_info: { air_terminal_type: 'AirTerminalSingleDuctVAVNoReheat', name: "#{loop_name} Diffuser" },
            zone_sizing: { htg_max_airflow_fraction: 1.0, clg_dsgn_sup_air_temp_f: 55.0, htg_dsgn_sup_air_temp_f: 104.0 }
          }
        end

        context = OpenstudioStandards::HVAC.apply_hvac(model, { air_system_info: air_specs, zone_info: zone_specs })
        air_specs.map { |spec| context.air_loop(spec[:name]) }
      end

      # The per-zone air-system spec for a PSZ-VAV.
      #
      # @return [Hash] the air_system_info entry
      def self.psz_vav_air_spec(loop_name, zone_name, op_sch, oa_sch, econ_max_oa_frac_sch, unitary)
        economizer = { reset_min_db: true, heat_recovery_bypass_ctrl_type: 'BypassWhenOAFlowGreaterThanMinimum' }
        economizer[:max_oa_frac_sch_name] = econ_max_oa_frac_sch.name.get if econ_max_oa_frac_sch
        {
          name: loop_name,
          design_info: { use_standard_sizing: true, des_heat_sat_f: 104.0 },
          availability: { schedule_name: op_sch, night_cycle: { control_type: 'CycleOnAny' } },
          oa_control: { controller_name: "#{loop_name} OA Sys Controller", ventilation: { min_oa_sch_name: oa_sch }, economizer: economizer },
          supply_components: [unitary],
          controls: [{ spm_type: 'SingleZoneReheat', name: "#{zone_name} Setpoint Manager SZ Reheat",
                       control_zone_name: zone_name, min_setpt_f: 55.0, max_setpt_f: 104.0 }]
        }
      end

      # The SingleZoneVAV unitary system spec inside a PSZ-VAV air loop.
      #
      # @return [Hash] the AirLoopHVACUnitarySystem component spec
      def self.psz_vav_unitary_spec(loop_name, zone_name, op_sch, fan_type, heating_type,
                                    supplemental_heating_type, cooling_type, hot_water_loop, chilled_water_loop)
        {
          obj_type: 'AirLoopHVACUnitarySystem',
          name: "#{zone_name} Unitary PSZ-VAV",
          schedule_name: op_sch,
          control_type: 'SingleZoneVAV',
          control_zone_name: zone_name,
          max_supply_air_temp_f: 104.0,
          fan_operation: { placement: 'BlowThrough', op_mode_sch_name: 'AlwaysOn' },
          components: [
            { obj_type: 'FanVariableVolume', name: "#{loop_name} Fan", preset: fan_type, enduse_subcat: 'VAV System Fans', schedule_name: op_sch },
            psz_vav_cooling_coil(loop_name, cooling_type, chilled_water_loop),
            psz_heating_coil(loop_name, heating_type, hot_water_loop: hot_water_loop),
            psz_vav_supplemental_coil(loop_name, supplemental_heating_type)
          ]
        }
      end

      # The cooling coil spec for a PSZ-VAV: a chilled-water coil, or the variable-speed DX coil.
      #
      # @return [Hash] the cooling coil component spec
      def self.psz_vav_cooling_coil(loop_name, cooling_type, chilled_water_loop)
        if cooling_type == 'WaterCooled'
          { obj_type: 'CoilCoolingWater', name: "#{loop_name} Clg Coil", plant_loop_name: chilled_water_loop.name.get }
        else
          { obj_type: 'CoilCoolingDXVariableSpeed', name: "#{loop_name} Var spd DX AC Clg Coil",
            basin_heater_capacity_w: 10.0, basin_heater_setpoint_c: 2.0, nominal_speed_level: 1, speeds: [{}] }
        end
      end

      # The supplemental heating coil spec for a PSZ-VAV (the no-backup name differs from PSZ-AC).
      #
      # @return [Hash] the supplemental heating coil component spec
      def self.psz_vav_supplemental_coil(loop_name, supplemental_heating_type)
        case supplemental_heating_type
        when 'Electricity', 'Electric'
          { obj_type: 'CoilHeatingElectric', name: "#{loop_name} Electric Backup Htg Coil", role: 'supplemental' }
        when 'NaturalGas', 'Gas'
          { obj_type: 'CoilHeatingGas', name: "#{loop_name} Gas Backup Htg Coil", role: 'supplemental' }
        else
          { obj_type: 'CoilHeatingElectric', name: "#{loop_name} No Backup Heat", schedule_name: 'AlwaysOff', capacity_w: 0.0, role: 'supplemental' }
        end
      end

      # Compose a multi-zone VAV reheat system (one air loop serving all zones), equivalent to
      # +model_add_vav_reheat+.
      #
      # Covers the air-cooled / gas configuration: a variable-volume fan, a gas or electric main
      # heating coil, a two-speed DX cooling coil, an outdoor air system with fixed-minimum
      # ventilation, and a VAV reheat (gas/electric) or no-reheat terminal per zone. Water coils
      # (a hot or chilled water loop), water reheat, and return plenums are not yet convertible and
      # raise.
      #
      # @param model [OpenStudio::Model::Model] the model
      # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] the zones to serve
      # @param system_name [String, nil] the loop name (defaults to "<n> Zone VAV")
      # @param heating_type [String, nil] main heating coil type ('Electricity', else gas)
      # @param reheat_type [String, nil] terminal reheat type ('NaturalGas'/'Gas', 'Electricity', or nil)
      # @param hot_water_loop [OpenStudio::Model::PlantLoop, nil] hot water loop (unsupported)
      # @param chilled_water_loop [OpenStudio::Model::PlantLoop, nil] chilled water loop (unsupported)
      # @param return_plenum [OpenStudio::Model::ThermalZone, nil] return plenum zone (unsupported)
      # @param hvac_op_sch [OpenStudio::Model::Schedule, nil] HVAC operating schedule (defaults to always on)
      # @param oa_damper_sch [OpenStudio::Model::Schedule, nil] OA damper schedule
      # @param fan_efficiency [Double] fan total efficiency
      # @param fan_motor_efficiency [Double] fan motor efficiency
      # @param fan_pressure_rise [Double] fan pressure rise (in H2O)
      # @param min_sys_airflow_ratio [Double, Symbol] central heating maximum system air flow ratio, the
      #   fraction of the cooling design flow the central heating coil is sized to heat; :autosize (the
      #   default) lets EnergyPlus derive it from the zones' heating design flows, a number pins it
      # @param vav_sizing_option [String] SizingSystem sizing option
      # @param econo_ctrl_mthd [String, nil] economizer control type
      # @return [OpenStudio::Model::AirLoopHVAC] the created air loop
      def self.vav_reheat(model, thermal_zones,
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
        raise NotImplementedError, 'vav_reheat composer does not yet support a return plenum' unless return_plenum.nil?
        raise ArgumentError, 'water reheat requires a hot water loop' if reheat_type == 'Water' && hot_water_loop.nil?

        loop_name = system_name || "#{thermal_zones.size} Zone VAV"
        op_sch = hvac_op_sch ? hvac_op_sch.name.get : 'AlwaysOn'

        # Pre-create the supply-air temperature schedule (55 F cooling design supply temperature).
        supply_sch = 'Supply Air Temp - 55.0F'
        OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model, OpenStudio.convert(55.0, 'F', 'C').get,
                                                                        name: supply_sch, schedule_type_limit: 'Temperature')

        main_heat = vav_main_heating_coil(loop_name, heating_type, hot_water_loop)
        fan = { obj_type: 'FanVariableVolume', name: "#{loop_name} Fan", preset: 'VAV_System_Fan',
                fan_total_eff: fan_efficiency, motor_eff: fan_motor_efficiency, pressure_rise_inh2o: fan_pressure_rise,
                enduse_subcat: 'VAV System Fans', schedule_name: 'AlwaysOn' }
        economizer = { reset_min_db: true }
        economizer[:type] = econo_ctrl_mthd if econo_ctrl_mthd

        air_spec = {
          name: loop_name,
          design_info: { use_standard_sizing: true, min_sys_airflow_ratio: sizing_ratio(min_sys_airflow_ratio), sizing_option: vav_sizing_option },
          availability: { schedule_name: op_sch, night_cycle: { control_type: 'CycleOnAny', run_time_s: 1800 } },
          oa_control: { controller_name: "#{loop_name} OA Controller",
                        ventilation: { min_limit_type: 'FixedMinimum', controller_mv_name: "#{loop_name} Vent Controller", sys_oa_method: 'ZoneSum' },
                        economizer: economizer },
          # inlet-to-outlet order: cooling coil, heating coil, fan
          supply_components: [vav_cooling_coil(loop_name, chilled_water_loop), main_heat, fan],
          controls: [{ spm_type: 'Scheduled', name: "#{loop_name} Supply Air Setpoint Manager", spm_sch_name: supply_sch }]
        }

        zone_specs = thermal_zones.map { |zone| vav_zone_spec(loop_name, zone.name.to_s, reheat_type, hot_water_loop) }

        context = OpenstudioStandards::HVAC.apply_hvac(model, { air_system_info: [air_spec], zone_info: zone_specs })
        context.air_loop(loop_name)
      end

      # The main heating coil spec for a VAV reheat air handler: a hot-water coil when a hot water
      # loop is given (rated temperatures from the loop), otherwise electric or gas.
      #
      # @return [Hash] the main heating coil component spec
      def self.vav_main_heating_coil(loop_name, heating_type, hot_water_loop)
        if hot_water_loop
          water_heating_coil("#{loop_name} Main Htg Coil", hot_water_loop, eat_f: 45.0, lat_f: 55.0)
        elsif heating_type == 'Electricity'
          { obj_type: 'CoilHeatingElectric', name: "#{loop_name} Main Electric Htg Coil" }
        else
          { obj_type: 'CoilHeatingGas', name: "#{loop_name} Main Gas Htg Coil" }
        end
      end

      # The cooling coil spec for a VAV reheat air handler: a chilled-water coil when a chilled water
      # loop is given, otherwise a two-speed DX coil.
      #
      # @return [Hash] the cooling coil component spec
      def self.vav_cooling_coil(loop_name, chilled_water_loop)
        if chilled_water_loop
          { obj_type: 'CoilCoolingWater', name: "#{loop_name} Clg Coil", plant_loop_name: chilled_water_loop.name.get }
        else
          { obj_type: 'CoilCoolingDXTwoSpeed', name: "#{loop_name} 2spd DX Clg Coil", preset: 'OS default' }
        end
      end

      # A hot-water heating coil spec with rated water temperatures derived from the loop sizing.
      # Entering/leaving air temperatures are optional; when omitted the coil keeps its defaults.
      #
      # @return [Hash] the water heating coil component spec
      def self.water_heating_coil(name, hot_water_loop, eat_f: nil, lat_f: nil)
        entering_c = hot_water_loop.sizingPlant.designLoopExitTemperature
        leaving_c = entering_c - hot_water_loop.sizingPlant.loopDesignTemperatureDifference
        spec = {
          obj_type: 'CoilHeatingWater', name: name, plant_loop_name: hot_water_loop.name.get,
          ewt_c: entering_c, lwt_c: leaving_c
        }
        spec[:eat_f] = eat_f if eat_f
        spec[:lat_f] = lat_f if lat_f
        spec
      end

      # The per-zone zone-info spec for a VAV reheat system.
      #
      # @return [Hash] the zone_info entry
      def self.vav_zone_spec(loop_name, zone_name, reheat_type, hot_water_loop)
        reheat = %w[NaturalGas Gas Electricity Water].include?(reheat_type)
        # Water reheat uses a 0.2 minimum damper position, gas/electric use 0.3.
        min_flow_frac = %w[NaturalGas Gas Electricity].include?(reheat_type) ? 0.3 : 0.2
        terminal =
          if reheat
            {
              air_terminal_type: 'AirTerminalSingleDuctVAVReheat', name: "#{zone_name} VAV Terminal",
              vav: { min_flow_input_method: 'Constant', damper_action: 'Normal', max_reheat_air_temp_f: 104.0, min_flow_frac: min_flow_frac },
              reheat: { coil_info: vav_reheat_coil(zone_name, reheat_type, hot_water_loop) }
            }
          else
            {
              air_terminal_type: 'AirTerminalSingleDuctVAVNoReheat', name: "#{zone_name} VAV Terminal",
              vav: { min_flow_input_method: 'Constant', min_flow_frac: 0.2 }
            }
          end
        {
          zone_name: zone_name,
          air_loop_name: loop_name,
          air_terminal_info: terminal,
          zone_sizing: vav_zone_sizing(reheat)
        }
      end

      # The reheat coil spec for a VAV reheat terminal (gas, electric, or hot water).
      #
      # @return [Hash] the reheat coil component spec
      def self.vav_reheat_coil(zone_name, reheat_type, hot_water_loop)
        case reheat_type
        when 'Electricity'
          { obj_type: 'CoilHeatingElectric', name: "#{zone_name} Electric Reheat Coil" }
        when 'Water'
          water_heating_coil("#{zone_name} Reheat Coil", hot_water_loop, eat_f: 55.0, lat_f: 104.0)
        else # NaturalGas / Gas
          { obj_type: 'CoilHeatingGas', name: "#{zone_name} Gas Reheat Coil" }
        end
      end

      # The zone sizing spec for a VAV reheat (or no-reheat) zone.
      #
      # The design_info spelling of a central heating maximum system air flow ratio argument.
      #
      # @param ratio [Double, Symbol, String, nil] a number, or :autosize / 'autosize' / nil
      # @return [Double, String] the number, or 'autosize'
      def self.sizing_ratio(ratio)
        return 'autosize' if ratio.nil? || ratio == :autosize || ratio == 'autosize'

        ratio
      end

      # @return [Hash] the zone_sizing spec
      def self.vav_zone_sizing(reheat)
        sizing = { clg_dsgn_airflow_method: 'DesignDayWithLimit', htg_max_airflow_fraction: 1.0, clg_dsgn_sup_air_temp_f: 55.0 }
        if reheat
          sizing[:htg_dsgn_airflow_method] = 'DesignDay'
          sizing[:htg_dsgn_sup_air_temp_f] = 104.0
        end
        sizing
      end

      # Compose a packaged multi-zone VAV system, equivalent to +model_add_pvav+.
      #
      # One air loop serving all zones with a variable-volume fan, a gas / electric / hot-water main
      # heating coil, a two-speed DX or chilled-water cooling coil, and a VAV reheat terminal per zone
      # (electric reheat, or hot-water reheat when a hot water loop is given and electric_reheat is
      # false). Return plenums are not yet convertible and raise.
      #
      # @param model [OpenStudio::Model::Model] the model
      # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] the zones to serve
      # @param system_name [String, nil] the loop name (defaults to "<n> Zone PVAV")
      # @param return_plenum [OpenStudio::Model::ThermalZone, nil] return plenum zone (unsupported)
      # @param hot_water_loop [OpenStudio::Model::PlantLoop, nil] hot water loop
      # @param chilled_water_loop [OpenStudio::Model::PlantLoop, nil] chilled water loop
      # @param heating_type [String, nil] main heating coil type ('Electricity', else gas) when no hot water loop
      # @param electric_reheat [Boolean] force electric reheat coils
      # @param hvac_op_sch [OpenStudio::Model::Schedule, nil] HVAC operating schedule
      # @param oa_damper_sch [OpenStudio::Model::Schedule, nil] OA damper schedule
      # @param econo_ctrl_mthd [String, nil] economizer control type
      # @return [OpenStudio::Model::AirLoopHVAC] the created air loop
      def self.pvav(model, thermal_zones,
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
        raise NotImplementedError, 'pvav composer does not yet support a return plenum' unless return_plenum.nil?

        loop_name = system_name || "#{thermal_zones.size} Zone PVAV"
        op_sch = hvac_op_sch ? hvac_op_sch.name.get : 'AlwaysOn'
        oa_sch = oa_damper_sch ? oa_damper_sch.name.get : 'AlwaysOn'
        # Zone heating design temperature is raised to 122 F except with a low-temperature hot water loop.
        low_temp_hw = hot_water_loop && hot_water_loop.sizingPlant.designLoopExitTemperature < OpenStudio.convert(140.0, 'F', 'C').get
        zn_htg_f = low_temp_hw ? 104.0 : 122.0

        supply_sch = 'Supply Air Temp - 55.0F'
        OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model, OpenStudio.convert(55.0, 'F', 'C').get,
                                                                        name: supply_sch, schedule_type_limit: 'Temperature')

        economizer = { reset_min_db: true }
        economizer[:type] = econo_ctrl_mthd if econo_ctrl_mthd
        air_spec = {
          name: loop_name,
          design_info: { use_standard_sizing: true, min_sys_airflow_ratio: sizing_ratio(min_sys_airflow_ratio) },
          availability: { schedule_name: op_sch, night_cycle: { control_type: 'CycleOnAny', run_time_s: 1800 } },
          oa_control: { controller_name: "#{loop_name} OA Controller",
                        ventilation: { min_limit_type: 'FixedMinimum', min_oa_sch_name: oa_sch,
                                       controller_mv_name: "#{loop_name} Mechanical Ventilation Controller", sys_oa_method: 'ZoneSum' },
                        economizer: economizer },
          supply_components: [
            vav_cooling_coil(loop_name, chilled_water_loop),
            vav_main_heating_coil(loop_name, heating_type, hot_water_loop),
            { obj_type: 'FanVariableVolume', name: "#{loop_name} Fan", preset: 'VAV_default', schedule_name: 'AlwaysOn' }
          ],
          controls: [{ spm_type: 'Scheduled', name: "#{loop_name} Supply Air Setpoint Manager", spm_sch_name: supply_sch }]
        }

        water_reheat = !electric_reheat && !hot_water_loop.nil?
        zone_specs = thermal_zones.map { |zone| pvav_zone_spec(loop_name, zone.name.to_s, water_reheat, hot_water_loop, zn_htg_f) }

        context = OpenstudioStandards::HVAC.apply_hvac(model, { air_system_info: [air_spec], zone_info: zone_specs })
        context.air_loop(loop_name)
      end

      # The per-zone zone-info spec for a packaged VAV system (always a reheat terminal).
      #
      # @return [Hash] the zone_info entry
      def self.pvav_zone_spec(loop_name, zone_name, water_reheat, hot_water_loop, zn_htg_f)
        coil = if water_reheat
                 water_heating_coil("#{zone_name} Reheat Coil", hot_water_loop, eat_f: 55.0, lat_f: zn_htg_f)
               else
                 { obj_type: 'CoilHeatingElectric', name: "#{zone_name} Electric Reheat Coil" }
               end
        {
          zone_name: zone_name,
          air_loop_name: loop_name,
          air_terminal_info: {
            air_terminal_type: 'AirTerminalSingleDuctVAVReheat', name: "#{zone_name} VAV Terminal",
            vav: { min_flow_input_method: 'Constant', damper_action: 'Normal', max_reheat_air_temp_f: zn_htg_f, min_flow_frac: water_reheat ? 0.2 : 0.3 },
            reheat: { coil_info: coil }
          },
          zone_sizing: { htg_max_airflow_fraction: 1.0, clg_dsgn_sup_air_temp_f: 55.0, htg_dsgn_sup_air_temp_f: zn_htg_f }
        }
      end

      # Compose a multi-zone constant-air-volume (CAV) system, equivalent to +model_add_cav+.
      #
      # One air loop serving all zones with a constant-volume fan, a hot-water main heating coil
      # (a hot water loop is required), a two-speed DX or chilled-water cooling coil, and a reheat
      # terminal per zone with hot-water reheat. Return plenums are not yet convertible and raise.
      #
      # @param model [OpenStudio::Model::Model] the model
      # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] the zones to serve
      # @param system_name [String, nil] the loop name (defaults to "<n> Zone CAV")
      # @param hot_water_loop [OpenStudio::Model::PlantLoop] the hot water loop (required)
      # @param chilled_water_loop [OpenStudio::Model::PlantLoop, nil] chilled water loop
      # @param hvac_op_sch [OpenStudio::Model::Schedule, nil] HVAC operating schedule
      # @param oa_damper_sch [OpenStudio::Model::Schedule, nil] OA damper schedule
      # @param fan_efficiency [Double] fan total efficiency
      # @param fan_motor_efficiency [Double] fan motor efficiency
      # @param fan_pressure_rise [Double] fan pressure rise (in H2O)
      # @return [OpenStudio::Model::AirLoopHVAC] the created air loop
      def self.cav(model, thermal_zones,
                   system_name: nil,
                   hot_water_loop: nil,
                   chilled_water_loop: nil,
                   hvac_op_sch: nil,
                   oa_damper_sch: nil,
                   fan_efficiency: 0.62,
                   fan_motor_efficiency: 0.9,
                   fan_pressure_rise: 4.0)
        raise ArgumentError, 'cav composer requires a hot water loop' if hot_water_loop.nil?

        loop_name = system_name || "#{thermal_zones.size} Zone CAV"
        op_sch = hvac_op_sch ? hvac_op_sch.name.get : 'AlwaysOn'
        oa_sch = oa_damper_sch ? oa_damper_sch.name.get : 'AlwaysOn'

        # CAV raises the heating supply temperature to 62 F and the zone heating supply to 122 F.
        supply_sch = 'Supply Air Temp - 55.0F'
        OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model, OpenStudio.convert(55.0, 'F', 'C').get,
                                                                        name: supply_sch, schedule_type_limit: 'Temperature')

        air_spec = {
          name: loop_name,
          design_info: { use_standard_sizing: true, des_heat_sat_f: 62.0, min_sys_airflow_ratio: 1.0 },
          availability: { schedule_name: op_sch, night_cycle: { control_type: 'CycleOnAny' } },
          oa_control: { controller_name: "#{loop_name} OA Controller",
                        ventilation: { min_limit_type: 'FixedMinimum', min_oa_frac_sch_name: oa_sch,
                                       controller_mv_name: "#{loop_name} Vent Controller", sys_oa_method: 'ZoneSum' },
                        economizer: { reset_min_db: true } },
          supply_components: [
            vav_cooling_coil(loop_name, chilled_water_loop),
            water_heating_coil("#{loop_name} Main Htg Coil", hot_water_loop, eat_f: 45.0, lat_f: 62.0),
            { obj_type: 'FanConstantVolume', name: "#{loop_name} Fan", preset: 'Packaged_RTU_SZ_AC_CAV_Fan',
              fan_total_eff: fan_efficiency, motor_eff: fan_motor_efficiency, pressure_rise_inh2o: fan_pressure_rise,
              enduse_subcat: 'CAV System Fans', schedule_name: 'AlwaysOn' }
          ],
          controls: [{ spm_type: 'Scheduled', name: "#{loop_name} Supply Air Setpoint Manager", spm_sch_name: supply_sch }]
        }

        zone_specs = thermal_zones.map { |zone| cav_zone_spec(loop_name, zone.name.to_s, hot_water_loop) }

        context = OpenstudioStandards::HVAC.apply_hvac(model, { air_system_info: [air_spec], zone_info: zone_specs })
        context.air_loop(loop_name)
      end

      # The per-zone zone-info spec for a CAV system (hot-water reheat terminal, no damper action).
      #
      # @return [Hash] the zone_info entry
      def self.cav_zone_spec(loop_name, zone_name, hot_water_loop)
        {
          zone_name: zone_name,
          air_loop_name: loop_name,
          air_terminal_info: {
            air_terminal_type: 'AirTerminalSingleDuctVAVReheat', name: "#{zone_name} VAV Terminal",
            vav: { min_flow_input_method: 'Constant', max_flow_per_area_reheat_m2: 0.0, max_flow_frac_reheat: 0.5,
                   max_reheat_air_temp_f: 122.0, min_flow_frac: 0.2 },
            reheat: { coil_info: water_heating_coil("#{zone_name} Reheat Coil", hot_water_loop, eat_f: 62.0, lat_f: 122.0) }
          },
          zone_sizing: { clg_dsgn_airflow_method: 'DesignDayWithLimit', htg_dsgn_airflow_method: 'DesignDay',
                         htg_max_airflow_fraction: 1.0, clg_dsgn_sup_air_temp_f: 55.0, htg_dsgn_sup_air_temp_f: 122.0 }
        }
      end

      # Compose a multi-zone VAV system with parallel fan-powered boxes, equivalent to
      # +model_add_vav_pfp_boxes+.
      #
      # One air loop with a variable-volume fan, an electric main heating coil, a chilled-water
      # cooling coil (a chilled water loop is required), and a parallel PIU reheat terminal (a
      # constant-volume terminal fan plus an electric reheat coil) per zone.
      #
      # @param model [OpenStudio::Model::Model] the model
      # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] the zones to serve
      # @param system_name [String, nil] the loop name
      # @param chilled_water_loop [OpenStudio::Model::PlantLoop] the chilled water loop (required)
      # @param hvac_op_sch [OpenStudio::Model::Schedule, nil] HVAC operating schedule
      # @param oa_damper_sch [OpenStudio::Model::Schedule, nil] OA damper schedule (unused, kept for signature parity)
      # @param fan_efficiency [Double] fan total efficiency
      # @param fan_motor_efficiency [Double] fan motor efficiency
      # @param fan_pressure_rise [Double] fan pressure rise (in H2O)
      # @return [OpenStudio::Model::AirLoopHVAC] the created air loop
      def self.vav_pfp_boxes(model, thermal_zones,
                             system_name: nil,
                             chilled_water_loop: nil,
                             hvac_op_sch: nil,
                             oa_damper_sch: nil,
                             fan_efficiency: 0.62,
                             fan_motor_efficiency: 0.9,
                             fan_pressure_rise: 4.0,
                             min_sys_airflow_ratio: :autosize)
        raise ArgumentError, 'vav_pfp_boxes composer requires a chilled water loop' if chilled_water_loop.nil?

        loop_name = system_name || "#{thermal_zones.size} Zone VAV with PFP Boxes and Reheat"
        op_sch = hvac_op_sch ? hvac_op_sch.name.get : 'AlwaysOn'

        supply_sch = 'Supply Air Temp - 55.0F'
        OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model, OpenStudio.convert(55.0, 'F', 'C').get,
                                                                        name: supply_sch, schedule_type_limit: 'Temperature')

        air_spec = {
          name: loop_name,
          design_info: { use_standard_sizing: true, min_sys_airflow_ratio: sizing_ratio(min_sys_airflow_ratio) },
          availability: { schedule_name: op_sch, night_cycle: { control_type: 'CycleOnAny' } },
          oa_control: { controller_name: "#{loop_name} OA Controller",
                        ventilation: { min_limit_type: 'FixedMinimum', controller_mv_name: "#{loop_name} Vent Controller", sys_oa_method: 'ZoneSum' },
                        economizer: { reset_min_db: true } },
          supply_components: [
            { obj_type: 'CoilCoolingWater', name: "#{loop_name} Clg Coil", plant_loop_name: chilled_water_loop.name.get },
            { obj_type: 'CoilHeatingElectric', name: "#{loop_name} Htg Coil" },
            { obj_type: 'FanVariableVolume', name: "#{loop_name} Fan", preset: 'VAV_System_Fan',
              fan_total_eff: fan_efficiency, motor_eff: fan_motor_efficiency, pressure_rise_inh2o: fan_pressure_rise,
              enduse_subcat: 'VAV System Fans', schedule_name: 'AlwaysOn' }
          ],
          controls: [{ spm_type: 'Scheduled', name: "#{loop_name} Supply Air Setpoint Manager", spm_sch_name: supply_sch }]
        }

        zone_specs = thermal_zones.map { |zone| pfp_zone_spec(loop_name, zone.name.to_s) }

        context = OpenstudioStandards::HVAC.apply_hvac(model, { air_system_info: [air_spec], zone_info: zone_specs })
        context.air_loop(loop_name)
      end

      # Compose a packaged multi-zone VAV system with parallel fan-powered boxes, equivalent to
      # +model_add_pvav_pfp_boxes+.
      #
      # Like {vav_pfp_boxes} but packaged: an electric main heating coil, a two-speed DX (or, when a
      # chilled water loop is given, chilled-water) cooling coil, and a minimum-OA schedule.
      #
      # @param model [OpenStudio::Model::Model] the model
      # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] the zones to serve
      # @param system_name [String, nil] the loop name
      # @param chilled_water_loop [OpenStudio::Model::PlantLoop, nil] chilled water loop (DX cooling when nil)
      # @param hvac_op_sch [OpenStudio::Model::Schedule, nil] HVAC operating schedule
      # @param oa_damper_sch [OpenStudio::Model::Schedule, nil] OA damper schedule
      # @param fan_efficiency [Double] fan total efficiency
      # @param fan_motor_efficiency [Double] fan motor efficiency
      # @param fan_pressure_rise [Double] fan pressure rise (in H2O)
      # @return [OpenStudio::Model::AirLoopHVAC] the created air loop
      def self.pvav_pfp_boxes(model, thermal_zones,
                              system_name: nil,
                              chilled_water_loop: nil,
                              hvac_op_sch: nil,
                              oa_damper_sch: nil,
                              fan_efficiency: 0.62,
                              fan_motor_efficiency: 0.9,
                              fan_pressure_rise: 4.0,
                              min_sys_airflow_ratio: :autosize)
        loop_name = system_name || "#{thermal_zones.size} Zone PVAV with PFP Boxes and Reheat"
        op_sch = hvac_op_sch ? hvac_op_sch.name.get : 'AlwaysOn'
        oa_sch = oa_damper_sch ? oa_damper_sch.name.get : 'AlwaysOn'

        supply_sch = 'Supply Air Temp - 55.0F'
        OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model, OpenStudio.convert(55.0, 'F', 'C').get,
                                                                        name: supply_sch, schedule_type_limit: 'Temperature')

        air_spec = {
          name: loop_name,
          design_info: { use_standard_sizing: true, min_sys_airflow_ratio: sizing_ratio(min_sys_airflow_ratio) },
          availability: { schedule_name: op_sch, night_cycle: { control_type: 'CycleOnAny' } },
          oa_control: { controller_name: "#{loop_name} OA Controller",
                        ventilation: { min_limit_type: 'FixedMinimum', min_oa_sch_name: oa_sch,
                                       controller_mv_name: "#{loop_name} Vent Controller", sys_oa_method: 'ZoneSum' },
                        economizer: { reset_min_db: true } },
          supply_components: [
            vav_cooling_coil(loop_name, chilled_water_loop),
            { obj_type: 'CoilHeatingElectric', name: "#{loop_name} Main Htg Coil" },
            { obj_type: 'FanVariableVolume', name: "#{loop_name} Fan", preset: 'VAV_System_Fan',
              fan_total_eff: fan_efficiency, motor_eff: fan_motor_efficiency, pressure_rise_inh2o: fan_pressure_rise,
              enduse_subcat: 'VAV System Fans', schedule_name: 'AlwaysOn' }
          ],
          controls: [{ spm_type: 'Scheduled', name: "#{loop_name} Supply Air Setpoint Manager", spm_sch_name: supply_sch }]
        }

        zone_specs = thermal_zones.map { |zone| pfp_zone_spec(loop_name, zone.name.to_s) }

        context = OpenstudioStandards::HVAC.apply_hvac(model, { air_system_info: [air_spec], zone_info: zone_specs })
        context.air_loop(loop_name)
      end

      # The per-zone zone-info spec for a fan-powered box system (parallel PIU terminal).
      #
      # @return [Hash] the zone_info entry
      def self.pfp_zone_spec(loop_name, zone_name)
        {
          zone_name: zone_name,
          air_loop_name: loop_name,
          air_terminal_info: {
            air_terminal_type: 'AirTerminalSingleDuctParallelPIUReheat', name: "#{zone_name} PFP Term",
            piu: {
              fan_data: { obj_type: 'FanConstantVolume', name: "#{zone_name} PFP Term Fan", preset: 'PFP_Fan' },
              coil_data: { obj_type: 'CoilHeatingElectric', name: "#{zone_name} Electric Reheat Coil" }
            }
          },
          zone_sizing: { clg_dsgn_airflow_method: 'DesignDay', htg_dsgn_airflow_method: 'DesignDay',
                         htg_max_airflow_fraction: 1.0, clg_dsgn_sup_air_temp_f: 55.0, htg_dsgn_sup_air_temp_f: 104.0 }
        }
      end

      # Compose per-zone furnace / central-AC systems, equivalent to +model_add_furnace_central_ac+.
      #
      # One air loop per zone with a unitary system holding a gas furnace heating coil (when heating)
      # and a residential single-speed DX cooling coil (when cooling), a residential fan, an
      # uncontrolled diffuser, and an optional outdoor air intake.
      #
      # @param model [OpenStudio::Model::Model] the model
      # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] the zones to serve
      # @param heating [Boolean] include a gas furnace heating coil
      # @param cooling [Boolean] include a DX cooling coil
      # @param ventilation [Boolean] include an outdoor air intake
      # @return [Array<OpenStudio::Model::AirLoopHVAC>] the created air loops
      def self.furnace_central_ac(model, thermal_zones, heating: true, cooling: false, ventilation: false)
        equip_name = if heating && cooling then 'Central Heating and AC'
                     elsif heating then 'Furnace'
                     elsif cooling then 'Central AC'
                     else raise ArgumentError, 'furnace_central_ac requires heating or cooling'
                     end

        evap_fan_power = 0.365 / OpenStudio.convert(1.0, 'cfm', 'm^3/s').get
        cop_no_fan = OpenstudioStandards::HVAC.eer_to_cop_no_fan(11.1)
        gas_eff = OpenstudioStandards::HVAC.afue_to_thermal_eff(0.78)

        air_specs = []
        zone_specs = []
        thermal_zones.each do |zone|
          loop_name = "#{zone.name} #{equip_name}"
          air_specs << {
            name: loop_name,
            design_info: { use_standard_sizing: true, des_heat_sat_f: 122.0, sizing_option: 'NonCoincident',
                           all_oa_in_cooling: true, all_oa_in_heating: true },
            supply_components: [furnace_unitary_spec(loop_name, zone.name.to_s, heating, cooling, ventilation, gas_eff, cop_no_fan, evap_fan_power)],
            oa_control: ventilation ? { controller_name: "#{loop_name} OA Controller", economizer: { reset_min_db: true } } : nil
          }.compact
          # The unit serves this zone alone, so a zone with no design load would give the loop no air
          # flow at all; DesignDayWithLimit keeps the zone's minimum air flow per floor area as a floor.
          zone_specs << {
            zone_name: zone.name.to_s, air_loop_name: loop_name,
            air_terminal_info: { air_terminal_type: 'AirTerminalSingleDuctConstantVolumeNoReheat', name: "#{zone.name} Direct Air" },
            zone_sizing: { clg_dsgn_airflow_method: 'DesignDayWithLimit' }
          }
        end

        context = OpenstudioStandards::HVAC.apply_hvac(model, { air_system_info: air_specs, zone_info: zone_specs })
        air_specs.map { |spec| context.air_loop(spec[:name]) }
      end

      # The unitary system spec for a furnace / central-AC air loop.
      #
      # @return [Hash] the AirLoopHVACUnitarySystem component spec
      def self.furnace_unitary_spec(loop_name, zone_name, heating, cooling, ventilation, gas_eff, cop_no_fan, evap_fan_power)
        airflows = {}
        airflows[:heating_m3s] = 0.0 unless heating
        airflows[:cooling_m3s] = 0.0 unless cooling
        airflows[:no_load_m3s] = 0.0 unless ventilation

        components = [{ obj_type: 'FanOnOff', name: "#{loop_name} Supply Fan", preset: 'Residential_HVAC_Fan',
                        enduse_subcat: 'Residential HVAC Fans', schedule_name: 'AlwaysOn' }]
        if cooling
          components << { obj_type: 'CoilCoolingDXSingleSpeed', name: "#{loop_name} Cooling Coil", preset: 'Residential Central AC',
                         rated_cop: cop_no_fan, sens_heat_ratio: 0.73, condenser_type: 'AirCooled',
                         evap_fan_power_w_per_m3s: evap_fan_power, condensate_removal_time_s: 1000.0, moisture_evap_ratio: 1.5,
                         max_cycling_rate: 3.0, latent_capacity_time_constant_s: 45.0,
                         crankcase_heater_capacity_w: 0.0, crankcase_max_oat_f: 55.0 }
        end
        components << { obj_type: 'CoilHeatingGas', name: "#{loop_name} Heating Coil", eff_percent: gas_eff } if heating

        spec = {
          obj_type: 'AirLoopHVACUnitarySystem', name: "#{loop_name} Unitary System",
          schedule_name: 'AlwaysOn', max_supply_air_temp_f: 122.0, control_zone_name: zone_name,
          fan_operation: { placement: 'BlowThrough', op_mode_sch_name: 'AlwaysOff' },
          components: components
        }
        spec[:operating_airflows] = airflows unless airflows.empty?
        spec
      end

      # Compose a dedicated outdoor air system (one air loop serving all zones with outdoor air),
      # equivalent to +model_add_doas+.
      #
      # A 100%-outdoor-air air handler sized on the ventilation requirement: a constant- or
      # variable-volume supply fan, a heat-pump (electric backup + single-speed DX) or hot-water
      # heating coil, a two-speed DX or chilled-water cooling coil, an outdoor air system, an optional
      # exhaust fan upstream of the OA mixing box, and an outdoor-air-reset supply-air setpoint. Each
      # zone with a nonzero design outdoor air requirement gets an uncontrolled (DOASCV), VAV no-reheat
      # (DOASVAV), or VAV reheat (DOASVAVReheat) terminal assigned first in the load sequence with a
      # zero sequential load fraction, and is sized to account for the DOAS. Returns +false+ (adding
      # nothing) when the zones' combined outdoor air requirement is zero, matching the legacy method.
      #
      # @param model [OpenStudio::Model::Model] the model
      # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] the zones to serve
      # @param system_name [String, nil] the loop name (defaults to "<n> Zone DOAS")
      # @param doas_type [String] 'DOASCV', 'DOASVAV', or 'DOASVAVReheat'
      # @param hot_water_loop [OpenStudio::Model::PlantLoop, nil] hot water loop for water heating coils
      # @param chilled_water_loop [OpenStudio::Model::PlantLoop, nil] chilled water loop for a water cooling coil
      # @param hvac_op_sch [OpenStudio::Model::Schedule, nil] HVAC operating schedule (defaults to always on)
      # @param min_oa_sch [OpenStudio::Model::Schedule, nil] minimum outdoor air schedule
      # @param min_frac_oa_sch [OpenStudio::Model::Schedule, nil] minimum outdoor air fraction schedule (defaults to always on)
      # @param fan_maximum_flow_rate [Double, nil] supply fan maximum flow rate (cfm)
      # @param econo_ctrl_mthd [String] economizer control type
      # @param include_exhaust_fan [Boolean] add an exhaust fan
      # @param demand_control_ventilation [Boolean] enable demand-controlled ventilation
      # @param doas_control_strategy [String] dedicated outdoor air system control strategy
      # @param clg_dsgn_sup_air_temp [Double] cooling design supply air temperature (F)
      # @param htg_dsgn_sup_air_temp [Double] heating design supply air temperature (F)
      # @return [OpenStudio::Model::AirLoopHVAC, false] the air loop, or false when the OA requirement is zero
      def self.doas(model, thermal_zones,
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
        raise NotImplementedError, 'doas composer does not yet support fan_maximum_flow_rate (the preset fan builder does not forward a maximum flow rate)' unless fan_maximum_flow_rate.nil?

        # Skip the system entirely when the combined OA requirement is zero (simulations would fail).
        oa_zones = thermal_zones.select { |zone| OpenstudioStandards::ThermalZone.thermal_zone_get_outdoor_airflow_rate(zone) > 0 }
        return false if oa_zones.empty?

        loop_name = system_name || "#{thermal_zones.size} Zone DOAS"
        op_sch = hvac_op_sch ? hvac_op_sch.name.get : 'AlwaysOn'
        clg_f = clg_dsgn_sup_air_temp || 60.0
        htg_f = htg_dsgn_sup_air_temp || 70.0
        variable = doas_type != 'DOASCV'
        fan_preset = variable ? 'Variable_DOAS_Fan' : 'Constant_DOAS_Fan'
        economizing = econo_ctrl_mthd != 'NoEconomizer'

        supply_fan = { obj_type: variable ? 'FanVariableVolume' : 'FanConstantVolume', name: 'DOAS Supply Fan',
                       preset: fan_preset, enduse_subcat: 'DOAS Fans', schedule_name: 'AlwaysOn' }

        # Supply components in airflow order (nearest the OA mixing box first): cooling coil, heating
        # coil(s), then the supply fan at the discharge.
        supply = [doas_cooling_coil(loop_name, chilled_water_loop)]
        supply.concat(doas_heating_coils(loop_name, hot_water_loop))
        supply << supply_fan

        air_spec = {
          name: loop_name,
          design_info: { des_cool_sat_f: clg_f, des_heat_sat_f: htg_f, load_type: 'VentilationRequirement',
                         sizing_option: 'Coincident', all_oa_in_cooling: true, all_oa_in_heating: true,
                         central_heating_max_flow_ratio: 1.0 },
          availability: { schedule_name: op_sch, night_cycle: { control_type: 'CycleOnAnyZoneFansOnly' } },
          oa_control: doas_oa_control(loop_name, econo_ctrl_mthd, min_oa_sch, min_frac_oa_sch, demand_control_ventilation),
          supply_components: supply,
          controls: [{ spm_type: 'OutdoorAirReset', name: "#{loop_name} SAT Reset", ctrl_var: 'Temperature',
                       oat_low_f: 55.0, setpoint_at_oat_low_f: htg_f, oat_high_f: 70.0, setpoint_at_oat_high_f: clg_f }]
        }
        if include_exhaust_fan
          exhaust_pr = [doas_fan_preset_pressure_inh2o(fan_preset) - 1.0, 1.0].max
          air_spec[:supply_inlet_components] = [
            { obj_type: variable ? 'FanVariableVolume' : 'FanConstantVolume', name: 'DOAS Exhaust Fan',
              preset: fan_preset, enduse_subcat: 'DOAS Fans', schedule_name: 'AlwaysOn', pressure_rise_override_inh2o: exhaust_pr }
          ]
        end

        zone_specs = oa_zones.map { |zone| doas_zone_spec(loop_name, zone.name.to_s, doas_type, hot_water_loop, demand_control_ventilation, economizing, clg_f, htg_f, doas_control_strategy) }

        context = OpenstudioStandards::HVAC.apply_hvac(model, { air_system_info: [air_spec], zone_info: zone_specs })
        context.air_loop(loop_name)
      end

      # The DOAS cooling coil spec: a chilled-water coil when a chilled water loop is given, otherwise
      # a two-speed DX coil (OS-default curves).
      #
      # @return [Hash] the cooling coil component spec
      def self.doas_cooling_coil(loop_name, chilled_water_loop)
        if chilled_water_loop
          { obj_type: 'CoilCoolingWater', name: "#{loop_name} Clg Coil", plant_loop_name: chilled_water_loop.name.get }
        else
          { obj_type: 'CoilCoolingDXTwoSpeed', name: "#{loop_name} 2spd DX Clg Coil", preset: 'OS default' }
        end
      end

      # The DOAS heating coil spec(s), in airflow order: a single hot-water coil (0.0001 controller
      # convergence tolerance) when a hot water loop is given, otherwise a heat-pump pair — a
      # single-speed DX coil upstream of an electric backup coil.
      #
      # @return [Array<Hash>] the heating coil component specs
      def self.doas_heating_coils(loop_name, hot_water_loop)
        if hot_water_loop
          entering_c = hot_water_loop.sizingPlant.designLoopExitTemperature
          leaving_c = entering_c - hot_water_loop.sizingPlant.loopDesignTemperatureDifference
          [{ obj_type: 'CoilHeatingWater', name: "#{loop_name} Htg Coil", plant_loop_name: hot_water_loop.name.get,
             ewt_c: entering_c, lwt_c: leaving_c, eat_c: 16.6, lat_c: 32.2, controller_convergence_tolerance: 0.0001 }]
        else
          [{ obj_type: 'CoilHeatingDXSingleSpeed', name: "#{loop_name} Htg Coil", preset: 'default' },
           { obj_type: 'CoilHeatingElectric', name: "#{loop_name} Backup Htg Coil" }]
        end
      end

      # The DOAS outdoor air controller spec, reproducing the legacy controller: a fixed-minimum
      # ventilation limit with a minimum OA fraction schedule and a mechanical ventilation controller
      # (ZoneSum, optional DCV), and an economizer whose limits are all reset with heat-recovery bypass
      # within the economizer limits.
      #
      # @return [Hash] the oa_control spec
      def self.doas_oa_control(loop_name, econo_ctrl_mthd, min_oa_sch, min_frac_oa_sch, dcv)
        ventilation = {
          min_limit_type: 'FixedMinimum',
          min_oa_frac_sch_name: min_frac_oa_sch ? min_frac_oa_sch.name.get : 'AlwaysOn',
          controller_mv_name: "#{loop_name} Mechanical Ventilation Controller",
          sys_oa_method: 'ZoneSum'
        }
        # The legacy method overwrites any supplied minimum OA schedule with always-on before setting it.
        ventilation[:min_oa_sch_name] = 'AlwaysOn' unless min_oa_sch.nil?
        ventilation[:dcv] = true if dcv
        {
          controller_name: "#{loop_name} Outdoor Air Controller",
          ventilation: ventilation,
          economizer: { type: econo_ctrl_mthd, reset_min_db: true, reset_max_db: true, reset_max_enthalpy: true,
                        reset_max_oa_frac_sch: true, heat_recovery_bypass_ctrl_type: 'BypassWhenWithinEconomizerLimits' }
        }
      end

      # The per-zone zone-info spec for a DOAS: the terminal (uncontrolled, VAV no-reheat, or VAV
      # reheat) assigned first in the load sequence with a zero sequential load fraction (or a full
      # sequential cooling fraction when economizing), and DOAS-aware zone sizing.
      #
      # @return [Hash] the zone_info entry
      def self.doas_zone_spec(loop_name, zone_name, doas_type, hot_water_loop, dcv, economizing, clg_f, htg_f, control_strategy)
        {
          zone_name: zone_name,
          air_loop_name: loop_name,
          air_terminal_info: doas_terminal(zone_name, doas_type, hot_water_loop, dcv, economizing),
          zone_sizing: { account_for_doas: true, doas_control_strategy: control_strategy,
                         doas_low_setpoint_f: clg_f, doas_high_setpoint_f: htg_f, htg_max_airflow_fraction: 1.0 }
        }
      end

      # The DOAS air terminal spec for a zone, selected by DOAS type. All types set the DOAS load
      # sequence (priority 1, zero sequential fractions; full sequential cooling when economizing);
      # the VAV types add a constant minimum-flow method and, under DCV, terminal outdoor-air control.
      #
      # @return [Hash] the air_terminal_info spec
      def self.doas_terminal(zone_name, doas_type, hot_water_loop, dcv, economizing)
        terminal = {
          name: "#{zone_name} Air Terminal",
          cool_priority: 1, heat_priority: 1,
          sequential_cooling_fraction: 0.0, sequential_heating_fraction: 0.0
        }
        # When economizing, the DOAS meets the cooling load first by overriding the cooling fraction to 1.
        terminal[:sequential_cooling_fraction_override] = 1.0 if economizing
        case doas_type
        when 'DOASVAVReheat'
          coil = if hot_water_loop
                   { obj_type: 'CoilHeatingWater', name: "#{zone_name} Reheat Coil", plant_loop_name: hot_water_loop.name.get }
                 else
                   { obj_type: 'CoilHeatingElectric', name: "#{zone_name} Electric Reheat Coil" }
                 end
          terminal[:air_terminal_type] = 'AirTerminalSingleDuctVAVReheat'
          terminal[:vav] = { min_flow_input_method: 'Constant', control_for_oa: dcv }
          terminal[:reheat] = { coil_info: coil }
        when 'DOASVAV'
          terminal[:air_terminal_type] = 'AirTerminalSingleDuctVAVNoReheat'
          terminal[:vav] = { min_flow_input_method: 'Constant', min_flow_frac: 0.1, control_for_oa: dcv }
        else # DOASCV
          terminal[:air_terminal_type] = 'AirTerminalSingleDuctConstantVolumeNoReheat'
        end
        terminal
      end

      # Compose the default DOE-prototype dedicated outdoor air system, equivalent to
      # +model_add_doas_cold_supply+.
      #
      # A simpler cold-supply sibling of {doas}: a constant-volume supply fan (no exhaust fan), a
      # heat-pump (electric backup + single-speed DX) or hot-water heating coil, a two-speed DX or
      # chilled-water cooling coil, an outdoor air system with a fixed economizer, an outdoor-air-reset
      # supply-air setpoint, and an uncontrolled terminal on every zone (no load-sequence override).
      # Each zone is sized for a cold-supply DOAS. Returns +false+ (adding nothing) when the zones'
      # combined outdoor air requirement is zero.
      #
      # The legacy +energy_recovery: true+ path references an undefined +zone+ variable and raises, so
      # this composer raises a clear error for it rather than reproducing broken behavior.
      #
      # @param model [OpenStudio::Model::Model] the model
      # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] the zones to serve
      # @param system_name [String, nil] the loop name (defaults to "<n> Zone DOAS")
      # @param hot_water_loop [OpenStudio::Model::PlantLoop, nil] hot water loop for a water heating coil
      # @param chilled_water_loop [OpenStudio::Model::PlantLoop, nil] chilled water loop for a water cooling coil
      # @param hvac_op_sch [OpenStudio::Model::Schedule, nil] HVAC operating schedule (defaults to always on)
      # @param min_oa_sch [OpenStudio::Model::Schedule, nil] minimum outdoor air schedule (defaults to always on)
      # @param min_frac_oa_sch [OpenStudio::Model::Schedule, nil] minimum outdoor air fraction schedule (defaults to always on)
      # @param fan_maximum_flow_rate [Double, nil] supply fan maximum flow rate (cfm) (unsupported)
      # @param econo_ctrl_mthd [String] economizer control type
      # @param energy_recovery [Boolean] add an ERV (unsupported: the legacy path is broken)
      # @param doas_control_strategy [String] accepted for signature parity; the legacy method hardcodes 'ColdSupplyAir'
      # @param clg_dsgn_sup_air_temp [Double] cooling design supply air temperature (F)
      # @param htg_dsgn_sup_air_temp [Double] heating design supply air temperature (F)
      # @return [OpenStudio::Model::AirLoopHVAC, false] the air loop, or false when the OA requirement is zero
      def self.doas_cold_supply(model, thermal_zones,
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
        raise NotImplementedError, 'doas_cold_supply composer does not support fan_maximum_flow_rate (the preset fan builder does not forward a maximum flow rate)' unless fan_maximum_flow_rate.nil?
        raise NotImplementedError, 'doas_cold_supply composer does not support energy_recovery (the legacy energy_recovery path references an undefined variable and raises)' if energy_recovery

        # Skip the system when no zone requires outdoor air (simulations would fail); otherwise every
        # zone is served (unlike the per-zone-skip in the general DOAS).
        return false if thermal_zones.none? { |zone| OpenstudioStandards::ThermalZone.thermal_zone_get_outdoor_airflow_rate(zone) > 0 }

        loop_name = system_name || "#{thermal_zones.size} Zone DOAS"
        op_sch = hvac_op_sch ? hvac_op_sch.name.get : 'AlwaysOn'
        clg_f = clg_dsgn_sup_air_temp || 55.0
        htg_f = htg_dsgn_sup_air_temp || 60.0

        supply = [doas_cooling_coil(loop_name, chilled_water_loop)]
        supply.concat(doas_heating_coils(loop_name, hot_water_loop))
        supply << { obj_type: 'FanConstantVolume', name: 'DOAS Supply Fan', preset: 'Constant_DOAS_Fan',
                    enduse_subcat: 'DOAS Fans', schedule_name: 'AlwaysOn' }

        air_spec = {
          name: loop_name,
          design_info: { des_cool_sat_f: clg_f, des_heat_sat_f: htg_f, load_type: 'VentilationRequirement',
                         sizing_option: 'Coincident', all_oa_in_cooling: true, all_oa_in_heating: true,
                         central_heating_max_flow_ratio: 1.0 },
          availability: { schedule_name: op_sch, night_cycle: { control_type: 'CycleOnAny' } },
          oa_control: doas_cold_supply_oa_control(loop_name, econo_ctrl_mthd, min_oa_sch, min_frac_oa_sch),
          supply_components: supply,
          controls: [{ spm_type: 'OutdoorAirReset', name: "#{loop_name} SAT Reset", ctrl_var: 'Temperature',
                       oat_low_f: 60.0, setpoint_at_oat_low_f: htg_f, oat_high_f: 70.0, setpoint_at_oat_high_f: clg_f }]
        }

        zone_specs = thermal_zones.map do |zone|
          {
            zone_name: zone.name.to_s,
            air_loop_name: loop_name,
            air_terminal_info: { air_terminal_type: 'AirTerminalSingleDuctConstantVolumeNoReheat', name: "#{zone.name} Air Terminal" },
            zone_sizing: { account_for_doas: true, doas_control_strategy: 'ColdSupplyAir',
                           doas_low_setpoint_f: clg_f, doas_high_setpoint_f: htg_f }
          }
        end

        context = OpenstudioStandards::HVAC.apply_hvac(model, { air_system_info: [air_spec], zone_info: zone_specs })
        context.air_loop(loop_name)
      end

      # The cold-supply DOAS outdoor air controller spec: a fixed-minimum ventilation limit with the
      # minimum OA and OA-fraction schedules and a fixed economizer whose limits are all reset with
      # heat-recovery bypass within the economizer limits. Unlike the general DOAS, the mechanical
      # ventilation controller is left at its defaults.
      #
      # @return [Hash] the oa_control spec
      def self.doas_cold_supply_oa_control(loop_name, econo_ctrl_mthd, min_oa_sch, min_frac_oa_sch)
        {
          controller_name: "#{loop_name} OA Controller",
          ventilation: {
            min_limit_type: 'FixedMinimum',
            min_oa_sch_name: min_oa_sch ? min_oa_sch.name.get : 'AlwaysOn',
            min_oa_frac_sch_name: min_frac_oa_sch ? min_frac_oa_sch.name.get : 'AlwaysOn'
          },
          economizer: { type: econo_ctrl_mthd, reset_min_db: true, reset_max_db: true, reset_max_enthalpy: true,
                        reset_max_oa_frac_sch: true, heat_recovery_bypass_ctrl_type: 'BypassWhenWithinEconomizerLimits' }
        }
      end

      # Climate zones cold enough (winter design below about -20 C) that a CRAC needs an economizer to
      # avoid the cooling coil operating below its EnergyPlus low-temperature limit.
      CRAC_COLD_CLIMATES = %w[
        ASHRAE\ 169-2006-6A ASHRAE\ 169-2006-6B ASHRAE\ 169-2006-7A ASHRAE\ 169-2006-7B
        ASHRAE\ 169-2006-8A ASHRAE\ 169-2006-8B ASHRAE\ 169-2013-6A ASHRAE\ 169-2013-6B
        ASHRAE\ 169-2013-7A ASHRAE\ 169-2013-7B ASHRAE\ 169-2013-8A ASHRAE\ 169-2013-8B
      ].freeze

      # Compose computer-room air conditioners (one air loop per zone), equivalent to +model_add_crac+.
      #
      # A single-zone data-center air handler per zone: a CRAC-preset fan, a single- or two-speed DX
      # cooling coil, a steam humidifier with a minimum-humidity setpoint on its outlet and a zone
      # humidistat, an outdoor air system (with a fixed-dry-bulb economizer in cold climates), a
      # scheduled supply-air setpoint, and a VAV no-reheat diffuser.
      #
      # @param model [OpenStudio::Model::Model] the model
      # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] the zones to serve
      # @param climate_zone [String] the climate zone (selects the cold-climate economizer)
      # @param system_name [String, nil] the system name suffix (defaults to "CRAC")
      # @param hvac_op_sch [OpenStudio::Model::Schedule, nil] HVAC operating schedule (defaults to always on)
      # @param oa_damper_sch [OpenStudio::Model::Schedule, nil] OA damper schedule (defaults to always on)
      # @param fan_location [String] 'DrawThrough' or 'BlowThrough'
      # @param fan_type [String] 'ConstantVolume', 'VariableVolume', or 'Cycling'
      # @param cooling_type [String] 'Single Speed DX AC' or 'Two Speed DX AC'
      # @param supply_temp_sch [OpenStudio::Model::Schedule, nil] supply air temperature schedule (defaults to 55 F)
      # @param rel_hum_setp_sch [OpenStudio::Model::Schedule, nil] humidifying relative-humidity setpoint schedule (defaults to 8%)
      # @return [Array<OpenStudio::Model::AirLoopHVAC>] the created air loops
      def self.crac(model, thermal_zones, climate_zone,
                    system_name: nil,
                    hvac_op_sch: nil,
                    oa_damper_sch: nil,
                    fan_location: 'DrawThrough',
                    fan_type: 'ConstantVolume',
                    cooling_type: 'Single Speed DX AC',
                    supply_temp_sch: nil,
                    rel_hum_setp_sch: nil)
        fan_preset = crac_fan_preset(fan_type)
        fan_obj = fan_type == 'VariableVolume' ? 'FanVariableVolume' : 'FanConstantVolume'
        op_sch = hvac_op_sch ? hvac_op_sch.name.get : 'AlwaysOn'
        oa_sch = oa_damper_sch ? oa_damper_sch.name.get : 'AlwaysOn'
        cold = CRAC_COLD_CLIMATES.include?(climate_zone)

        supply_sch_name = data_center_supply_temp_schedule(model, supply_temp_sch)
        rh_sch_name = data_center_humidity_schedule(model, rel_hum_setp_sch, 8.0)

        air_specs = []
        zone_specs = []
        thermal_zones.each do |zone|
          loop_name = system_name.nil? ? "#{zone.name} CRAC" : "#{zone.name} #{system_name}"
          humidifier_name = "#{loop_name} Electric Steam Humidifier"
          fan = { obj_type: fan_obj, name: "#{loop_name} Fan", preset: fan_preset, schedule_name: op_sch }
          clg = crac_cooling_coil(loop_name, cooling_type)
          humidifier = { obj_type: 'HumidifierSteamElectric', name: humidifier_name }
          # supply airflow order (nearest the OA mixing box first)
          supply = fan_location == 'BlowThrough' ? [fan, clg, humidifier] : [clg, humidifier, fan]

          oa_control = { ventilation: { min_oa_sch_name: oa_sch } }
          oa_control[:economizer] = { type: 'FixedDryBulb' } if cold

          air_specs << {
            name: loop_name,
            design_info: { use_standard_sizing: true, des_preheat_sat_f: 64.4, des_precool_sat_f: 80.6,
                           des_heat_sat_f: 55.0, des_cool_sat_f: 55.0, min_sys_airflow_ratio: 0.05 },
            availability: { schedule_name: op_sch },
            oa_control: oa_control,
            supply_components: supply,
            controls: [
              { spm_type: 'Scheduled', name: 'CRAC supply air setpoint manager', spm_sch_name: supply_sch_name },
              { spm_type: 'SingleZoneHumidityMinimum', control_zone_name: zone.name.to_s, spm_node: humidifier_name }
            ]
          }
          zone_specs << {
            zone_name: zone.name.to_s,
            air_loop_name: loop_name,
            air_terminal_info: { air_terminal_type: 'AirTerminalSingleDuctVAVNoReheat', name: "#{loop_name} Diffuser",
                                 vav: { min_flow_input_method: 'Constant', min_flow_frac: 0.1 } },
            zone_sizing: { clg_dsgn_sup_air_temp_f: 55.0, htg_dsgn_sup_air_temp_f: 55.0 },
            humidistat: { humidifying_rh_sch_name: rh_sch_name }
          }
        end

        context = OpenstudioStandards::HVAC.apply_hvac(model, { air_system_info: air_specs, zone_info: zone_specs })
        air_specs.map { |spec| context.air_loop(spec[:name]) }
      end

      # The CRAC supply fan preset for a fan type.
      #
      # @return [String] the fan preset name
      def self.crac_fan_preset(fan_type)
        case fan_type
        when 'VariableVolume' then 'CRAC_VAV_fan'
        when 'ConstantVolume' then 'CRAC_CAV_fan'
        when 'Cycling' then 'CRAC_Cycling_fan'
        else raise ArgumentError, "crac composer does not support fan_type '#{fan_type}'"
        end
      end

      # The CRAC cooling coil spec: a single-speed (PSZ-AC curves) or two-speed (default curves) DX coil.
      #
      # @return [Hash] the cooling coil component spec
      def self.crac_cooling_coil(loop_name, cooling_type)
        case cooling_type
        when 'Single Speed DX AC'
          { obj_type: 'CoilCoolingDXSingleSpeed', name: "#{loop_name} 1spd DX AC Clg Coil", preset: 'PSZ-AC' }
        when 'Two Speed DX AC'
          { obj_type: 'CoilCoolingDXTwoSpeed', name: "#{loop_name} 2spd DX AC Clg Coil", preset: 'default' }
        else
          raise ArgumentError, "crac composer does not support cooling_type '#{cooling_type}'"
        end
      end

      # Compose a computer-room air handler (one air loop serving all zones), equivalent to
      # +model_add_crah+.
      #
      # A larger-data-center chilled-water air handler: a variable-volume fan, a chilled-water cooling
      # coil (a chilled water loop is required), a steam humidifier, an outdoor air system with a
      # fixed-minimum ventilation limit, a scheduled supply-air setpoint, and a VAV no-reheat terminal
      # per zone. Each zone gets a humidistat and a minimum-humidity setpoint manager on the shared
      # humidifier outlet — as in the legacy method, only the last survives on that node.
      #
      # @param model [OpenStudio::Model::Model] the model
      # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] the zones to serve
      # @param chilled_water_loop [OpenStudio::Model::PlantLoop] the chilled water loop (required)
      # @param system_name [String, nil] the loop name (defaults to "Data Center CRAH")
      # @param hvac_op_sch [OpenStudio::Model::Schedule, nil] HVAC operating schedule (defaults to always on)
      # @param oa_damper_sch [OpenStudio::Model::Schedule, nil] OA damper schedule (defaults to always on)
      # @param return_plenum [OpenStudio::Model::ThermalZone, nil] a return plenum zone for every zone
      # @param supply_temp_sch [OpenStudio::Model::Schedule, nil] supply air temperature schedule (defaults to 55 F)
      # @param rel_hum_setp_sch [OpenStudio::Model::Schedule, nil] humidifying relative-humidity setpoint schedule (defaults to 8%)
      # @return [OpenStudio::Model::AirLoopHVAC] the created air loop
      def self.crah(model, thermal_zones,
                    chilled_water_loop: nil,
                    system_name: nil,
                    hvac_op_sch: nil,
                    oa_damper_sch: nil,
                    return_plenum: nil,
                    supply_temp_sch: nil,
                    rel_hum_setp_sch: nil)
        raise ArgumentError, 'crah composer requires a chilled water loop' if chilled_water_loop.nil?

        loop_name = system_name || 'Data Center CRAH'
        op_sch = hvac_op_sch ? hvac_op_sch.name.get : 'AlwaysOn'
        oa_sch = oa_damper_sch ? oa_damper_sch.name.get : 'AlwaysOn'
        supply_sch_name = data_center_supply_temp_schedule(model, supply_temp_sch)
        rh_sch_name = data_center_humidity_schedule(model, rel_hum_setp_sch, 8.0)
        humidifier_name = "#{loop_name} Electric Steam Humidifier"

        controls = [{ spm_type: 'Scheduled', name: 'CRAH supply air setpoint manager', spm_sch_name: supply_sch_name }]
        # One minimum-humidity setpoint manager per zone, all on the humidifier outlet; OpenStudio keeps
        # only the last on the node, matching the legacy method.
        thermal_zones.each do |zone|
          controls << { spm_type: 'SingleZoneHumidityMinimum', control_zone_name: zone.name.to_s, spm_node: humidifier_name }
        end

        air_spec = {
          name: loop_name,
          design_info: { use_standard_sizing: true, des_preheat_sat_f: 64.4, des_precool_sat_f: 80.6,
                         des_heat_sat_f: 55.0, des_cool_sat_f: 55.0, min_sys_airflow_ratio: 0.3 },
          availability: { schedule_name: op_sch },
          oa_control: { controller_name: "#{loop_name} OA Controller",
                        ventilation: { min_limit_type: 'FixedMinimum', min_oa_sch_name: oa_sch,
                                       controller_mv_name: "#{loop_name} Vent Controller", sys_oa_method: 'ZoneSum' } },
          supply_components: [
            { obj_type: 'CoilCoolingWater', name: "#{loop_name} Water Clg Coil", plant_loop_name: chilled_water_loop.name.get, schedule_name: op_sch },
            { obj_type: 'HumidifierSteamElectric', name: humidifier_name },
            { obj_type: 'FanVariableVolume', name: "#{loop_name} Fan", preset: 'VAV_System_Fan', schedule_name: op_sch }
          ],
          controls: controls
        }

        zone_specs = thermal_zones.map do |zone|
          spec = {
            zone_name: zone.name.to_s,
            air_loop_name: loop_name,
            air_terminal_info: { air_terminal_type: 'AirTerminalSingleDuctVAVNoReheat', name: "#{zone.name} VAV terminal",
                                 vav: { min_flow_input_method: 'Constant', min_flow_frac: 0.1 } },
            zone_sizing: { clg_dsgn_sup_air_temp_f: 55.0, htg_dsgn_sup_air_temp_f: 55.0 },
            humidistat: { humidifying_rh_sch_name: rh_sch_name }
          }
          spec[:return_plenum_name] = return_plenum.name.to_s if return_plenum
          spec
        end

        context = OpenstudioStandards::HVAC.apply_hvac(model, { air_system_info: [air_spec], zone_info: zone_specs })
        context.air_loop(loop_name)
      end

      # Compose water-to-air heat-pump data-center systems (one air loop per zone), equivalent to
      # +model_add_data_center_hvac+.
      #
      # A single-zone PSZ-AC per zone whose unitary system holds a water-to-air heat pump (cooling and
      # heating coils on the heat pump loop) with an electric backup coil, a single-zone-reheat
      # setpoint, an outdoor air system, and an uncontrolled diffuser. A +main_data_center+ zone adds a
      # supplemental hot-water and electric preheat coil downstream of the unitary and a steam
      # humidifier with a minimum-humidity setpoint and a zone humidistat.
      #
      # @param model [OpenStudio::Model::Model] the model
      # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] the zones to serve
      # @param hot_water_loop [OpenStudio::Model::PlantLoop] hot water loop (used for the main-data-center preheat coil)
      # @param heat_pump_loop [OpenStudio::Model::PlantLoop] the heat pump (condenser) loop for the WAHP coils
      # @param system_name [String, nil] the system name suffix (defaults to "PSZ-AC Data Center")
      # @param hvac_op_sch [OpenStudio::Model::Schedule, nil] HVAC operating schedule (defaults to always on)
      # @param oa_damper_sch [OpenStudio::Model::Schedule, nil] OA damper schedule (defaults to always on)
      # @param rel_hum_setp_sch [OpenStudio::Model::Schedule, nil] humidifying relative-humidity setpoint schedule (defaults to 30%)
      # @param main_data_center [Boolean] add the supplemental preheat coils and humidification
      # @return [Array<OpenStudio::Model::AirLoopHVAC>] the created air loops
      def self.data_center_hvac(model, thermal_zones, hot_water_loop, heat_pump_loop,
                                system_name: nil,
                                hvac_op_sch: nil,
                                oa_damper_sch: nil,
                                rel_hum_setp_sch: nil,
                                main_data_center: false)
        op_sch = hvac_op_sch ? hvac_op_sch.name.get : 'AlwaysOn'
        oa_sch = oa_damper_sch ? oa_damper_sch.name.get : 'AlwaysOn'
        hp_name = heat_pump_loop.name.get
        # The legacy method creates this schedule unconditionally, even when it is only used by a main
        # data center's humidistat.
        rh_sch_name = data_center_humidity_schedule(model, rel_hum_setp_sch, 30.0, 'OfficeLarge DC_MinRelHumSetSch')

        air_specs = []
        zone_specs = []
        thermal_zones.each do |zone|
          loop_name = system_name.nil? ? "#{zone.name} PSZ-AC Data Center" : "#{zone.name} #{system_name}"
          humidifier_name = "#{loop_name} Electric Steam Humidifier"

          # supply airflow order (nearest the OA mixing box first): the unitary, then — for a main data
          # center — the humidifier and the supplemental preheat coils toward the zone.
          supply = [data_center_unitary_spec(loop_name, zone.name.to_s, op_sch, hp_name)]
          if main_data_center
            supply << { obj_type: 'HumidifierSteamElectric', name: humidifier_name, rated_capacity_m3s: 3.72e-5, rated_power_w: 100_000.0 }
            supply << { obj_type: 'CoilHeatingElectric', name: "#{loop_name} Electric Htg Coil" }
            supply << data_center_water_coil(loop_name, hot_water_loop)
          end

          controls = [{ spm_type: 'SingleZoneReheat', name: "#{zone.name} Setpoint Manager SZ Reheat",
                        control_zone_name: zone.name.to_s, min_setpt_f: 55.0, max_setpt_f: 104.0 }]
          controls << { spm_type: 'SingleZoneHumidityMinimum', control_zone_name: zone.name.to_s, spm_node: humidifier_name } if main_data_center

          air_specs << {
            name: loop_name,
            design_info: { use_standard_sizing: true, des_heat_sat_f: 104.0, min_sys_airflow_ratio: 1.0 },
            availability: { schedule_name: op_sch, night_cycle: { control_type: 'CycleOnAny' } },
            oa_control: { ventilation: { min_oa_sch_name: oa_sch }, economizer: { reset_min_db: true } },
            supply_components: supply,
            controls: controls
          }

          zone_spec = {
            zone_name: zone.name.to_s,
            air_loop_name: loop_name,
            air_terminal_info: { air_terminal_type: 'AirTerminalSingleDuctConstantVolumeNoReheat', name: "#{loop_name} Diffuser" },
            zone_sizing: { clg_dsgn_sup_air_temp_f: 55.0, htg_dsgn_sup_air_temp_f: 104.0 }
          }
          zone_spec[:humidistat] = { humidifying_rh_sch_name: rh_sch_name } if main_data_center
          zone_specs << zone_spec
        end

        context = OpenstudioStandards::HVAC.apply_hvac(model, { air_system_info: air_specs, zone_info: zone_specs })
        air_specs.map { |spec| context.air_loop(spec[:name]) }
      end

      # The water-to-air heat-pump unitary system spec for a data-center air loop: an on/off fan, the
      # WAHP cooling and heating coils on the heat pump loop, and an electric backup coil.
      #
      # @return [Hash] the AirLoopHVACUnitarySystem component spec
      def self.data_center_unitary_spec(loop_name, zone_name, op_sch, heat_pump_loop_name)
        {
          obj_type: 'AirLoopHVACUnitarySystem',
          name: "#{zone_name} Unitary HP",
          control_zone_name: zone_name,
          fan_operation: { placement: 'BlowThrough', op_mode_sch_name: 'AlwaysOn' },
          supplemental_max_oat_f: 40.0,
          components: [
            { obj_type: 'FanOnOff', name: "#{loop_name} Fan", preset: 'Packaged_RTU_SZ_AC_Cycling_Fan', schedule_name: op_sch },
            { obj_type: 'CoilCoolingWaterToAirHeatPump', name: "#{loop_name} Water-to-Air HP Clg Coil", preset: 'default', plant_loop_name: heat_pump_loop_name },
            { obj_type: 'CoilHeatingWaterToAirHeatPump', name: "#{loop_name} Water-to-Air HP Htg Coil", preset: 'default', plant_loop_name: heat_pump_loop_name },
            { obj_type: 'CoilHeatingElectric', name: "#{loop_name} Electric Backup Htg Coil", role: 'supplemental' }
          ]
        }
      end

      # The supplemental hot-water preheat coil spec for a main data center (rated water temperatures
      # from the loop; rated air 45 F in / 104 F out).
      #
      # @return [Hash] the CoilHeatingWater component spec
      def self.data_center_water_coil(loop_name, hot_water_loop)
        entering_c = hot_water_loop.sizingPlant.designLoopExitTemperature
        leaving_c = entering_c - hot_water_loop.sizingPlant.loopDesignTemperatureDifference
        { obj_type: 'CoilHeatingWater', name: "#{loop_name} Water Htg Coil", plant_loop_name: hot_water_loop.name.get,
          ewt_c: entering_c, lwt_c: leaving_c, eat_f: 45.0, lat_f: 104.0 }
      end

      # Get-or-create the shared data-center supply-air temperature schedule (55 F), referenced by name.
      #
      # @return [String] the schedule name
      def self.data_center_supply_temp_schedule(model, supply_temp_sch)
        return supply_temp_sch.name.get if supply_temp_sch

        name = 'AHU Supply Temp Sch'
        unless model.getScheduleByName(name).is_initialized
          OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model, OpenStudio.convert(55.0, 'F', 'C').get,
                                                                          name: name, schedule_type_limit: 'Temperature')
        end
        name
      end

      # Get-or-create a data-center humidifying relative-humidity setpoint schedule, referenced by name.
      #
      # @return [String] the schedule name
      def self.data_center_humidity_schedule(model, rel_hum_setp_sch, default_percent, name = 'DataCenter Humidity Setpoint Schedule')
        return rel_hum_setp_sch.name.get if rel_hum_setp_sch

        unless model.getScheduleByName(name).is_initialized
          OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model, default_percent, name: name)
        end
        name
      end

      # The pressure rise (in H2O) of a packaged typical-fan preset, read from the shared fan data.
      #
      # @param preset [String] the fan preset name
      # @return [Double, nil] the preset pressure rise (in H2O)
      def self.doas_fan_preset_pressure_inh2o(preset)
        data = JSON.parse(File.read(File.expand_path('../components/data/fans.json', __dir__)), symbolize_names: true)
        entry = data[:fans].find { |fan| fan[:name] == preset }
        entry && entry[:pressure_rise]
      end

      # Compose packaged terminal air conditioners (one per zone), equivalent to +model_add_ptac+.
      #
      # The first zone-equipment composer: a ZoneHVACPackagedTerminalAirConditioner per zone with a
      # packaged-terminal fan, a single- or two-speed DX cooling coil, and a gas / electric / hot-water
      # / no-heat coil, added directly to the zone (no air loop). Ventilation can be suppressed (zero
      # outdoor air) for units paired with a separate DOAS.
      #
      # @param model [OpenStudio::Model::Model] the model
      # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] the zones to serve
      # @param cooling_type [String] 'Two Speed DX AC' or 'Single Speed DX AC'
      # @param heating_type [String, nil] 'NaturalGas'/'Gas', 'Electricity'/'Electric', 'Water', or nil (no heat)
      # @param hot_water_loop [OpenStudio::Model::PlantLoop, nil] hot water loop for a water heating coil
      # @param fan_type [String] 'ConstantVolume' or 'Cycling'
      # @param ventilation [Boolean] supply ventilation air through the unit
      # @return [Array<OpenStudio::Model::ZoneHVACPackagedTerminalAirConditioner>] the created PTACs
      def self.ptac(model, thermal_zones,
                    cooling_type: 'Two Speed DX AC',
                    heating_type: 'Gas',
                    hot_water_loop: nil,
                    fan_type: 'Cycling',
                    ventilation: true)
        raise ArgumentError, 'ptac water heating requires a hot water loop' if heating_type == 'Water' && hot_water_loop.nil?

        fan_preset = fan_type == 'ConstantVolume' ? 'PTAC_CAV_Fan' : 'PTAC_Cycling_Fan'
        op_mode_sch = fan_type == 'ConstantVolume' ? 'AlwaysOn' : 'AlwaysOff'

        ptac_names = []
        zone_specs = thermal_zones.map do |zone|
          ptac_name = "#{zone.name} PTAC"
          ptac_names << ptac_name
          {
            zone_name: zone.name.to_s,
            zone_equipment: [{
              obj_type: 'ZoneHVACPackagedTerminalAirConditioner', name: ptac_name,
              fan_placement: 'DrawThrough', op_mode_sch_name: op_mode_sch, no_ventilation: !ventilation,
              components: [
                { obj_type: 'FanOnOff', name: "#{zone.name} PTAC Fan", preset: fan_preset },
                ptac_cooling_coil(zone.name.to_s, cooling_type),
                ptac_heating_coil(zone.name.to_s, heating_type, hot_water_loop)
              ]
            }],
            zone_sizing: { clg_dsgn_sup_air_temp_f: 57.0, htg_dsgn_sup_air_temp_f: 122.0,
                           clg_dsgn_sup_air_humidity_ratio: 0.008, htg_dsgn_sup_air_humidity_ratio: 0.008 }
          }
        end

        OpenstudioStandards::HVAC.apply_hvac(model, { zone_info: zone_specs })
        ptac_names.map { |name| model.getZoneHVACPackagedTerminalAirConditionerByName(name).get }
      end

      # The PTAC cooling coil spec: a two-speed (default curves) or single-speed (PTAC curves) DX coil.
      #
      # @return [Hash] the cooling coil component spec
      def self.ptac_cooling_coil(zone_name, cooling_type)
        case cooling_type
        when 'Two Speed DX AC'
          { obj_type: 'CoilCoolingDXTwoSpeed', name: "#{zone_name} PTAC 2spd DX AC Clg Coil", preset: 'default' }
        when 'Single Speed DX AC'
          { obj_type: 'CoilCoolingDXSingleSpeed', name: "#{zone_name} PTAC 1spd DX AC Clg Coil", preset: 'PTAC' }
        else
          raise ArgumentError, "ptac composer does not support cooling_type '#{cooling_type}'"
        end
      end

      # The PTAC heating coil spec: gas, electric, hot water, or a zero-capacity always-off no-heat coil.
      #
      # @return [Hash] the heating coil component spec
      def self.ptac_heating_coil(zone_name, heating_type, hot_water_loop)
        case heating_type
        when 'NaturalGas', 'Gas'
          { obj_type: 'CoilHeatingGas', name: "#{zone_name} PTAC Gas Htg Coil" }
        when 'Electricity', 'Electric'
          { obj_type: 'CoilHeatingElectric', name: "#{zone_name} PTAC Electric Htg Coil" }
        when 'Water'
          entering_c = hot_water_loop.sizingPlant.designLoopExitTemperature
          leaving_c = entering_c - hot_water_loop.sizingPlant.loopDesignTemperatureDifference
          # The legacy coil name is derived from the hot water loop, and it keeps the default rated air temperatures.
          { obj_type: 'CoilHeatingWater', name: "#{hot_water_loop.name} Water Htg Coil", plant_loop_name: hot_water_loop.name.get,
            ewt_c: entering_c, lwt_c: leaving_c, eat_c: 16.6, lat_c: 32.2 }
        when nil
          { obj_type: 'CoilHeatingElectric', name: "#{zone_name} PTAC No Heat", schedule_name: 'AlwaysOff', capacity_w: 0.0 }
        else
          raise ArgumentError, "ptac composer does not support heating_type '#{heating_type}'"
        end
      end

      # Compose packaged terminal heat pumps (one per zone), equivalent to +model_add_pthp+.
      #
      # A ZoneHVACPackagedTerminalHeatPump per zone with a packaged-terminal fan, a single-speed DX
      # (heat-pump) cooling coil, a single-speed DX heating coil, and an electric supplemental coil,
      # added directly to the zone.
      #
      # @param model [OpenStudio::Model::Model] the model
      # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] the zones to serve
      # @param fan_type [String] 'ConstantVolume' or 'Cycling'
      # @param ventilation [Boolean] supply ventilation air through the unit
      # @return [Array<OpenStudio::Model::ZoneHVACPackagedTerminalHeatPump>] the created PTHPs
      def self.pthp(model, thermal_zones, fan_type: 'Cycling', ventilation: true)
        fan_preset = fan_type == 'ConstantVolume' ? 'PTAC_CAV_Fan' : 'PTAC_Cycling_Fan'
        op_mode_sch = fan_type == 'ConstantVolume' ? 'AlwaysOn' : 'AlwaysOff'

        pthp_names = []
        zone_specs = thermal_zones.map do |zone|
          pthp_name = "#{zone.name} PTHP"
          pthp_names << pthp_name
          {
            zone_name: zone.name.to_s,
            zone_equipment: [{
              obj_type: 'ZoneHVACPackagedTerminalHeatPump', name: pthp_name,
              fan_placement: 'DrawThrough', op_mode_sch_name: op_mode_sch, no_ventilation: !ventilation,
              components: [
                { obj_type: 'FanOnOff', name: "#{zone.name} PTHP Fan", preset: fan_preset },
                { obj_type: 'CoilCoolingDXSingleSpeed', name: "#{zone.name} PTHP Clg Coil", preset: 'Heat Pump' },
                { obj_type: 'CoilHeatingDXSingleSpeed', name: "#{zone.name} PTHP Htg Coil", preset: 'default' },
                { obj_type: 'CoilHeatingElectric', name: "#{zone.name} PTHP Supplemental Htg Coil", role: 'supplemental' }
              ]
            }],
            zone_sizing: { clg_dsgn_sup_air_temp_f: 57.0, htg_dsgn_sup_air_temp_f: 122.0,
                           clg_dsgn_sup_air_humidity_ratio: 0.008, htg_dsgn_sup_air_humidity_ratio: 0.008 }
          }
        end

        OpenstudioStandards::HVAC.apply_hvac(model, { zone_info: zone_specs })
        pthp_names.map { |name| model.getZoneHVACPackagedTerminalHeatPumpByName(name).get }
      end

      # Compose unit heaters (one per zone), equivalent to +model_add_unitheater+.
      #
      # A ZoneHVACUnitHeater per zone with a unit-heater fan and a gas / electric / hot-water heating
      # coil, added directly to the zone. A hot-water coil requires a district-heating heating type and
      # a hot water loop.
      #
      # @param model [OpenStudio::Model::Model] the model
      # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] the zones to serve
      # @param hvac_op_sch [OpenStudio::Model::Schedule, nil] HVAC operating schedule (defaults to always on)
      # @param fan_control_type [String] the unit heater fan control type
      # @param fan_pressure_rise [Double] fan pressure rise (in H2O) — accepted for signature parity; the shared fan creator ignores it
      # @param heating_type [String] 'NaturalGas'/'Gas', 'Electricity'/'Electric', or a 'DistrictHeating*' type (with a hot water loop)
      # @param hot_water_loop [OpenStudio::Model::PlantLoop, nil] hot water loop for a water heating coil
      # @param rated_inlet_water_temperature [Double] rated inlet water temperature (F)
      # @param rated_outlet_water_temperature [Double] rated outlet water temperature (F)
      # @param rated_inlet_air_temperature [Double] rated inlet air temperature (F)
      # @param rated_outlet_air_temperature [Double] rated outlet air temperature (F)
      # @return [Array<OpenStudio::Model::ZoneHVACUnitHeater>] the created unit heaters
      def self.unitheater(model, thermal_zones,
                          hvac_op_sch: nil,
                          fan_control_type: 'ConstantVolume',
                          fan_pressure_rise: 0.2,
                          heating_type: nil,
                          hot_water_loop: nil,
                          rated_inlet_water_temperature: 180.0,
                          rated_outlet_water_temperature: 160.0,
                          rated_inlet_air_temperature: 60.0,
                          rated_outlet_air_temperature: 104.0)
        op_sch = hvac_op_sch ? hvac_op_sch.name.get : 'AlwaysOn'
        control_type = fan_control_type || 'ConstantVolume'

        unit_names = []
        zone_specs = thermal_zones.map do |zone|
          unit_name = "#{zone.name} Unit Heater"
          unit_names << unit_name
          {
            zone_name: zone.name.to_s,
            zone_equipment: [{
              obj_type: 'ZoneHVACUnitHeater', name: unit_name, schedule_name: op_sch, control_type: control_type,
              components: [
                { obj_type: 'FanConstantVolume', name: "#{zone.name} UnitHeater Fan", preset: 'Unit_Heater_Fan', schedule_name: op_sch },
                unitheater_heating_coil(zone.name.to_s, heating_type, hot_water_loop, op_sch,
                                        rated_inlet_water_temperature, rated_outlet_water_temperature,
                                        rated_inlet_air_temperature, rated_outlet_air_temperature)
              ]
            }],
            zone_sizing: { htg_max_airflow_fraction: 1.0, htg_dsgn_sup_air_temp_f: 122.0 }
          }
        end

        OpenstudioStandards::HVAC.apply_hvac(model, { zone_info: zone_specs })
        unit_names.map { |name| model.getZoneHVACUnitHeaterByName(name).get }
      end

      # The unit heater heating coil spec: gas, electric, or (for a district-heating type with a hot
      # water loop) a hot-water coil with the given rated temperatures.
      #
      # @return [Hash] the heating coil component spec
      def self.unitheater_heating_coil(zone_name, heating_type, hot_water_loop, op_sch, ewt_f, lwt_f, eat_f, lat_f)
        case heating_type
        when 'NaturalGas', 'Gas'
          { obj_type: 'CoilHeatingGas', name: "#{zone_name} UnitHeater Gas Htg Coil", schedule_name: op_sch }
        when 'Electricity', 'Electric'
          { obj_type: 'CoilHeatingElectric', name: "#{zone_name} UnitHeater Electric Htg Coil", schedule_name: op_sch }
        else
          if heating_type.to_s.include?('DistrictHeating') && hot_water_loop
            { obj_type: 'CoilHeatingWater', name: "#{zone_name} UnitHeater Water Htg Coil", plant_loop_name: hot_water_loop.name.get,
              ewt_f: ewt_f || 180.0, lwt_f: lwt_f || 160.0, eat_f: eat_f || 60.0, lat_f: lat_f || 104.0 }
          else
            raise ArgumentError, "unitheater composer does not support heating_type '#{heating_type}' (a district-heating type requires a hot water loop)"
          end
        end
      end

      # Compose four-pipe fan coil units (one per zone), equivalent to +model_add_four_pipe_fan_coil+.
      #
      # A ZoneHVACFourPipeFanCoil per zone with a constant- or variable-speed fan, a chilled-water
      # cooling coil (a chilled water loop is required), and a hot-water or zero-capacity no-heat coil,
      # added directly to the zone.
      #
      # @param model [OpenStudio::Model::Model] the model
      # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] the zones to serve
      # @param chilled_water_loop [OpenStudio::Model::PlantLoop] the chilled water loop (required)
      # @param hot_water_loop [OpenStudio::Model::PlantLoop, nil] hot water loop (a no-heat coil when nil)
      # @param ventilation [Boolean] supply ventilation air through the unit
      # @param capacity_control_method [String] the fan coil capacity control method
      # @return [Array<OpenStudio::Model::ZoneHVACFourPipeFanCoil>] the created fan coils
      def self.four_pipe_fan_coil(model, thermal_zones, chilled_water_loop,
                                  hot_water_loop: nil,
                                  ventilation: false,
                                  capacity_control_method: 'CyclingFan')
        raise ArgumentError, 'four_pipe_fan_coil composer requires a chilled water loop' if chilled_water_loop.nil?

        variable = %w[VariableFanVariableFlow VariableFanConstantFlow].include?(capacity_control_method)
        fan_preset = variable ? 'Fan_Coil_VarSpeed_Fan' : 'Fan_Coil_Fan'
        fan_obj = variable ? 'FanVariableVolume' : 'FanOnOff'
        fan_name = variable ? 'Fan Coil Variable Fan' : 'Fan Coil fan'

        fcu_names = []
        zone_specs = thermal_zones.map do |zone|
          fcu_name = "#{zone.name} FCU"
          fcu_names << fcu_name
          heating = if hot_water_loop
                      entering_c = hot_water_loop.sizingPlant.designLoopExitTemperature
                      leaving_c = entering_c - hot_water_loop.sizingPlant.loopDesignTemperatureDifference
                      { obj_type: 'CoilHeatingWater', name: "#{zone.name} FCU Heating Coil", plant_loop_name: hot_water_loop.name.get,
                        ewt_c: entering_c, lwt_c: leaving_c, eat_c: 16.6, lat_f: 104.0 }
                    else
                      { obj_type: 'CoilHeatingElectric', name: "#{zone.name} No Heat", schedule_name: 'AlwaysOff', capacity_w: 0.0 }
                    end
          {
            zone_name: zone.name.to_s,
            zone_equipment: [{
              obj_type: 'ZoneHVACFourPipeFanCoil', name: fcu_name, capacity_ctrl_method: capacity_control_method, no_ventilation: !ventilation,
              components: [
                { obj_type: fan_obj, name: "#{zone.name} #{fan_name}", preset: fan_preset, enduse_subcat: 'FCU Fans' },
                { obj_type: 'CoilCoolingWater', name: "#{zone.name} FCU Cooling Coil", plant_loop_name: chilled_water_loop.name.get },
                heating
              ]
            }],
            zone_sizing: { clg_dsgn_sup_air_temp_f: 55.0, htg_dsgn_sup_air_temp_f: 104.0 }
          }
        end

        OpenstudioStandards::HVAC.apply_hvac(model, { zone_info: zone_specs })
        fcu_names.map { |name| model.getZoneHVACFourPipeFanCoilByName(name).get }
      end

      # Compose baseboard heaters (one per zone), equivalent to +model_add_baseboard+.
      #
      # An electric convective baseboard per zone, or — when a hot water loop is given — a hydronic
      # convective baseboard with a hot-water baseboard coil on the loop, added directly to the zone.
      #
      # @param model [OpenStudio::Model::Model] the model
      # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] the zones to serve
      # @param hot_water_loop [OpenStudio::Model::PlantLoop, nil] hot water loop for hydronic baseboards
      # @return [Array<OpenStudio::Model::ModelObject>] the created baseboards
      def self.baseboard(model, thermal_zones, hot_water_loop: nil)
        baseboard_names = []
        zone_specs = thermal_zones.map do |zone|
          equipment =
            if hot_water_loop.nil?
              { obj_type: 'ZoneHVACBaseboardConvectiveElectric', name: "#{zone.name} Electric Baseboard" }
            else
              { obj_type: 'ZoneHVACBaseboardConvectiveWater', name: "#{zone.name} Hydronic Baseboard",
                hot_water_loop_name: hot_water_loop.name.get, coil_name: "#{zone.name} Hydronic Baseboard Coil" }
            end
          baseboard_names << equipment[:name]
          { zone_name: zone.name.to_s, zone_equipment: [equipment] }
        end

        OpenstudioStandards::HVAC.apply_hvac(model, { zone_info: zone_specs })
        baseboard_names.map do |name|
          if hot_water_loop.nil?
            model.getZoneHVACBaseboardConvectiveElectricByName(name).get
          else
            model.getZoneHVACBaseboardConvectiveWaterByName(name).get
          end
        end
      end

      # Compose window air conditioners (one per zone), equivalent to +model_add_window_ac+.
      #
      # A ZoneHVACPackagedTerminalAirConditioner per zone configured as a window unit: a window-AC fan,
      # a single-speed DX (window-AC) cooling coil, and an always-off zero-capacity electric heating
      # coil, added directly to the zone.
      #
      # @param model [OpenStudio::Model::Model] the model
      # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] the zones to serve
      # @return [Array<OpenStudio::Model::ZoneHVACPackagedTerminalAirConditioner>] the created units
      def self.window_ac(model, thermal_zones)
        cop = OpenStudio.convert(8.5, 'Btu/h', 'W').get

        ac_names = []
        zone_specs = thermal_zones.map do |zone|
          ac_name = "#{zone.name} Window AC"
          ac_names << ac_name
          {
            zone_name: zone.name.to_s,
            zone_equipment: [{
              obj_type: 'ZoneHVACPackagedTerminalAirConditioner', name: ac_name, op_mode_sch_name: 'AlwaysOff',
              components: [
                { obj_type: 'FanOnOff', name: "#{zone.name} Window AC Supply Fan", preset: 'Window_AC_Supply_Fan', enduse_subcat: 'Window AC Fans' },
                { obj_type: 'CoilCoolingDXSingleSpeed', name: "#{zone.name} Window AC Cooling Coil", preset: 'Window AC',
                  rated_cop: cop, sens_heat_ratio: 0.65, evap_fan_power_w_per_m3s: 773.3, evap_condenser_effectiveness: 0.9,
                  crankcase_max_oat_c: 10.0, basin_heater_setpoint_c: 2.0 },
                { obj_type: 'CoilHeatingElectric', name: "#{zone.name} Window AC Always Off Htg Coil", schedule_name: 'AlwaysOff', capacity_w: 0.0 }
              ]
            }]
          }
        end

        OpenstudioStandards::HVAC.apply_hvac(model, { zone_info: zone_specs })
        ac_names.map { |name| model.getZoneHVACPackagedTerminalAirConditionerByName(name).get }
      end

      # Compose zone water-source (water-to-air) heat pumps (one per zone), equivalent to
      # +model_add_water_source_hp+.
      #
      # A ZoneHVACWaterToAirHeatPump per zone with a water-source-HP fan, water-to-air heat-pump
      # cooling and heating coils on the condenser loop, and an electric supplemental coil.
      #
      # @param model [OpenStudio::Model::Model] the model
      # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] the zones to serve
      # @param condenser_loop [OpenStudio::Model::PlantLoop] the condenser loop for the heat pump coils
      # @param ventilation [Boolean] supply ventilation air through the unit
      # @return [Array<OpenStudio::Model::ZoneHVACWaterToAirHeatPump>] the created heat pumps
      def self.water_source_hp(model, thermal_zones, condenser_loop, ventilation: true)
        cond_name = condenser_loop.name.get

        wshp_names = []
        zone_specs = thermal_zones.map do |zone|
          wshp_name = "#{zone.name} WSHP"
          wshp_names << wshp_name
          {
            zone_name: zone.name.to_s,
            zone_equipment: [{
              obj_type: 'ZoneHVACWaterToAirHeatPump', name: wshp_name, no_ventilation: !ventilation,
              components: [
                { obj_type: 'FanOnOff', name: "#{zone.name} WSHP Fan", preset: 'WSHP_Fan' },
                { obj_type: 'CoilCoolingWaterToAirHeatPump', name: "#{zone.name} Water-to-Air HP Clg Coil", preset: 'default', plant_loop_name: cond_name },
                { obj_type: 'CoilHeatingWaterToAirHeatPump', name: "#{zone.name} Water-to-Air HP Htg Coil", preset: 'default', plant_loop_name: cond_name },
                { obj_type: 'CoilHeatingElectric', name: "#{zone.name} Supplemental Htg Coil", role: 'supplemental' }
              ]
            }]
          }
        end

        OpenstudioStandards::HVAC.apply_hvac(model, { zone_info: zone_specs })
        wshp_names.map { |name| model.getZoneHVACWaterToAirHeatPumpByName(name).get }
      end

      # Compose ideal loads air systems (one per zone), equivalent to +model_add_ideal_air_loads+.
      #
      # A ZoneHVACIdealLoadsAirSystem per zone with the given availability, limit, dehumidification,
      # ventilation, economizer, and heat-recovery settings. The +add_output_meters+ custom-meter path
      # is not declaratively expressible and raises.
      #
      # @param model [OpenStudio::Model::Model] the model
      # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] the zones to serve
      # @param hvac_op_sch [OpenStudio::Model::Schedule, nil] HVAC operating schedule (defaults to always on)
      # @param heat_avail_sch [OpenStudio::Model::Schedule, nil] heating availability schedule (defaults to always on)
      # @param cool_avail_sch [OpenStudio::Model::Schedule, nil] cooling availability schedule (defaults to always on)
      # @param heat_limit_type [String] heating limit type
      # @param cool_limit_type [String] cooling limit type
      # @param dehumid_limit_type [String] dehumidification control type
      # @param cool_sensible_heat_ratio [Double] cooling sensible heat ratio
      # @param humid_ctrl_type [String] humidification control type
      # @param include_outdoor_air [Boolean] reference the largest space's design outdoor air object
      # @param enable_dcv [Boolean] enable occupancy-schedule demand-controlled ventilation
      # @param econo_ctrl_mthd [String] outdoor air economizer type
      # @param heat_recovery_type [String] heat recovery type
      # @param heat_recovery_sensible_eff [Double] heat recovery sensible effectiveness
      # @param heat_recovery_latent_eff [Double] heat recovery latent effectiveness
      # @param add_output_meters [Boolean] add custom output meters (unsupported)
      # @return [Array<OpenStudio::Model::ZoneHVACIdealLoadsAirSystem>] the created ideal loads systems
      def self.ideal_air_loads(model, thermal_zones,
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
        raise NotImplementedError, 'ideal_air_loads composer does not support add_output_meters (custom meters are not declaratively expressible)' if add_output_meters

        op_sch = hvac_op_sch ? hvac_op_sch.name.get : 'AlwaysOn'
        heat_sch = heat_avail_sch ? heat_avail_sch.name.get : 'AlwaysOn'
        cool_sch = cool_avail_sch ? cool_avail_sch.name.get : 'AlwaysOn'

        ideal_names = []
        zone_specs = thermal_zones.map do |zone|
          ideal_name = "#{zone.name} Ideal Loads Air System"
          ideal_names << ideal_name
          equipment = {
            obj_type: 'ZoneHVACIdealLoadsAirSystem', name: ideal_name,
            schedule_name: op_sch, heat_avail_sch_name: heat_sch, cool_avail_sch_name: cool_sch,
            heat_limit_type: heat_limit_type, cool_limit_type: cool_limit_type,
            dehumid_limit_type: dehumid_limit_type, cool_sensible_heat_ratio: cool_sensible_heat_ratio,
            humid_ctrl_type: humid_ctrl_type, dcv_type: enable_dcv ? 'OccupancySchedule' : 'None',
            econo_ctrl_mthd: econo_ctrl_mthd, heat_recovery_type: heat_recovery_type,
            heat_recovery_sensible_eff: heat_recovery_sensible_eff, heat_recovery_latent_eff: heat_recovery_latent_eff
          }
          equipment[:design_oa_name] = ideal_loads_design_oa_name(zone) if include_outdoor_air
          { zone_name: zone.name.to_s, zone_equipment: [equipment], zone_sizing: { htg_max_airflow_fraction: 1.0 } }
        end

        OpenstudioStandards::HVAC.apply_hvac(model, { zone_info: zone_specs })
        ideal_names.map { |name| model.getZoneHVACIdealLoadsAirSystemByName(name).get }
      end

      # The name of the design outdoor air object of the zone's largest space, or nil when none.
      #
      # @param zone [OpenStudio::Model::ThermalZone] the zone
      # @return [String, nil] the design outdoor air object name
      def self.ideal_loads_design_oa_name(zone)
        # sorted first so an exact tie in floor area resolves to the same space every run
        largest_space = zone.spaces.sort.max_by(&:floorArea)
        return nil if largest_space.nil?

        design_oa = largest_space.designSpecificationOutdoorAir
        design_oa.is_initialized ? design_oa.get.name.get : nil
      end

      # Compose high-temperature radiant heaters (one per zone), equivalent to +model_add_high_temp_radiant+.
      #
      # A ZoneHVACHighTemperatureRadiant per zone with the given fuel type and combustion efficiency,
      # heated to the zone's existing heating setpoint schedule. Each zone must have a thermostat with a
      # heating setpoint schedule.
      #
      # @param model [OpenStudio::Model::Model] the model
      # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] the zones to serve
      # @param heating_type [String] 'NaturalGas'/'Gas' or 'Electric'
      # @param combustion_efficiency [Double] combustion efficiency (fraction)
      # @param control_type [String] the radiant temperature control type
      # @return [Array<OpenStudio::Model::ZoneHVACHighTemperatureRadiant>] the created radiant heaters
      def self.high_temp_radiant(model, thermal_zones,
                                 heating_type: 'NaturalGas',
                                 combustion_efficiency: 0.8,
                                 control_type: 'MeanAirTemperature')
        fuel = [nil, 'NaturalGas', 'Gas'].include?(heating_type) ? 'NaturalGas' : heating_type

        radiant_names = []
        zone_specs = thermal_zones.map do |zone|
          setpoint_sch = high_temp_radiant_setpoint_schedule(zone)
          radiant_name = "#{zone.name} High Temp Radiant"
          radiant_names << radiant_name
          {
            zone_name: zone.name.to_s,
            zone_equipment: [{
              obj_type: 'ZoneHVACHighTemperatureRadiant', name: radiant_name,
              heating_type: fuel, combustion_efficiency: combustion_efficiency, radiant_fraction: 0.8,
              heating_setpoint_sch_name: setpoint_sch, control_type: control_type, throttling_range_k: 2
            }]
          }
        end

        OpenstudioStandards::HVAC.apply_hvac(model, { zone_info: zone_specs })
        radiant_names.map { |name| model.getZoneHVACHighTemperatureRadiantByName(name).get }
      end

      # The name of a zone's heating setpoint schedule, from its dual-setpoint thermostat.
      #
      # @param zone [OpenStudio::Model::ThermalZone] the zone
      # @return [String] the heating setpoint schedule name
      # @raise [ArgumentError] when the zone has no thermostat heating setpoint schedule
      def self.high_temp_radiant_setpoint_schedule(zone)
        thermostat = zone.thermostatSetpointDualSetpoint
        schedule = thermostat.is_initialized ? thermostat.get.heatingSetpointTemperatureSchedule : OpenStudio::Model::OptionalSchedule.new
        raise ArgumentError, "high_temp_radiant requires a heating setpoint schedule on zone '#{zone.name}'" unless schedule.is_initialized

        schedule.get.name.get
      end

      # Compose a split-system air conditioner (one air loop serving all zones), equivalent to
      # +model_add_split_ac+.
      #
      # A constant-volume air handler with a DX cooling coil, an optional gas or heat-pump main heating
      # coil, an optional electric or gas backup coil, an outdoor air system, a single-zone-reheat
      # supply-air setpoint, and an uncontrolled diffuser per zone.
      #
      # @param model [OpenStudio::Model::Model] the model
      # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] the zones to serve
      # @param cooling_type [String] 'Two Speed DX AC', 'Single Speed DX AC', or 'Single Speed Heat Pump'
      # @param heating_type [String] 'Gas' or 'Single Speed Heat Pump'
      # @param supplemental_heating_type [String] 'Electric' or 'Gas' backup heat (or none)
      # @param fan_type [String] 'ConstantVolume' or 'Cycling'
      # @param hvac_op_sch [OpenStudio::Model::Schedule, nil] HVAC operating schedule (defaults to always on)
      # @param oa_damper_sch [OpenStudio::Model::Schedule, nil] OA damper schedule (defaults to always on)
      # @param econ_max_oa_frac_sch [OpenStudio::Model::Schedule, nil] economizer maximum OA fraction schedule
      # @return [OpenStudio::Model::AirLoopHVAC] the created air loop
      def self.split_ac(model, thermal_zones,
                        cooling_type: 'Two Speed DX AC',
                        heating_type: 'Single Speed Heat Pump',
                        supplemental_heating_type: 'Gas',
                        fan_type: 'Cycling',
                        hvac_op_sch: nil,
                        oa_damper_sch: nil,
                        econ_max_oa_frac_sch: nil)
        loop_name = "#{thermal_zones.map { |zone| zone.name }.join(' - ')} SAC"
        op_sch = hvac_op_sch ? hvac_op_sch.name.get : 'AlwaysOn'
        oa_sch = oa_damper_sch ? oa_damper_sch.name.get : 'AlwaysOn'
        fan_preset = fan_type == 'ConstantVolume' ? 'Split_AC_CAV_Fan' : 'Split_AC_Cycling_Fan'
        fan_obj = fan_type == 'ConstantVolume' ? 'FanConstantVolume' : 'FanOnOff'

        # supply airflow order (nearest the OA mixing box first): cooling, main heating, backup, fan
        supply = [split_ac_cooling_coil(loop_name, cooling_type),
                  split_ac_heating_coil(loop_name, heating_type),
                  split_ac_supplemental_coil(loop_name, supplemental_heating_type),
                  { obj_type: fan_obj, name: "#{loop_name} Fan", preset: fan_preset, enduse_subcat: 'CAV System Fans' }].compact

        economizer = { reset_min_db: true }
        economizer[:max_oa_frac_sch_name] = econ_max_oa_frac_sch.name.get if econ_max_oa_frac_sch
        air_spec = {
          name: loop_name,
          design_info: { use_standard_sizing: true, des_heat_sat_f: 122.0, min_sys_airflow_ratio: 1.0, sizing_option: 'NonCoincident' },
          availability: { schedule_name: op_sch },
          oa_control: { ventilation: { min_oa_sch_name: oa_sch }, economizer: economizer },
          supply_components: supply,
          controls: [{ spm_type: 'SingleZoneReheat', name: "#{loop_name} Setpoint Manager SZ Reheat",
                       control_zone_name: thermal_zones[0].name.to_s, min_setpt_f: 55.0, max_setpt_f: 122.0 }]
        }

        zone_specs = thermal_zones.map do |zone|
          {
            zone_name: zone.name.to_s, air_loop_name: loop_name,
            air_terminal_info: { air_terminal_type: 'AirTerminalSingleDuctConstantVolumeNoReheat', name: "#{zone.name} SAC Diffuser" },
            zone_sizing: { clg_dsgn_sup_air_temp_f: 55.0, htg_dsgn_sup_air_temp_f: 122.0,
                           clg_dsgn_sup_air_humidity_ratio: 0.008, htg_dsgn_sup_air_humidity_ratio: 0.008 }
          }
        end

        context = OpenstudioStandards::HVAC.apply_hvac(model, { air_system_info: [air_spec], zone_info: zone_specs })
        context.air_loop(loop_name)
      end

      # The split-AC cooling coil spec (two-speed default curves, single-speed Split-AC curves, or
      # single-speed Heat-Pump curves).
      #
      # @return [Hash] the cooling coil component spec
      def self.split_ac_cooling_coil(loop_name, cooling_type)
        case cooling_type
        when 'Two Speed DX AC'
          { obj_type: 'CoilCoolingDXTwoSpeed', name: "#{loop_name} 2spd DX AC Clg Coil", preset: 'default' }
        when 'Single Speed DX AC'
          { obj_type: 'CoilCoolingDXSingleSpeed', name: "#{loop_name} 1spd DX AC Clg Coil", preset: 'Split AC' }
        when 'Single Speed Heat Pump'
          { obj_type: 'CoilCoolingDXSingleSpeed', name: "#{loop_name} 1spd DX HP Clg Coil", preset: 'Heat Pump' }
        else
          raise ArgumentError, "split_ac composer does not support cooling_type '#{cooling_type}'"
        end
      end

      # The split-AC main heating coil spec: a gas coil (with a part-load-fraction curve) or a
      # single-speed DX heat-pump coil, or nil for no main heating.
      #
      # @return [Hash, nil] the heating coil component spec
      def self.split_ac_heating_coil(loop_name, heating_type)
        case heating_type
        when 'Gas'
          { obj_type: 'CoilHeatingGas', name: "#{loop_name} Gas Htg Coil", plf_curve_coeffs: [0.8, 0.2, 0.0, 0.0] }
        when 'Single Speed Heat Pump'
          { obj_type: 'CoilHeatingDXSingleSpeed', name: "#{loop_name} HP Htg Coil", preset: 'default' }
        end
      end

      # The split-AC backup heating coil spec (electric or gas), or nil for none.
      #
      # @return [Hash, nil] the supplemental heating coil component spec
      def self.split_ac_supplemental_coil(loop_name, supplemental_heating_type)
        case supplemental_heating_type
        when 'Electric'
          { obj_type: 'CoilHeatingElectric', name: "#{loop_name} Electric Backup Htg Coil" }
        when 'Gas'
          { obj_type: 'CoilHeatingGas', name: "#{loop_name} Gas Backup Htg Coil" }
        end
      end

      # Compose minisplit heat pumps (one air loop per zone), equivalent to +model_add_minisplit_hp+.
      #
      # A per-zone air loop whose unitary system holds a residential-minisplit DX heating coil (with
      # cold-climate operating limits), a DX cooling coil, an electric backup coil, and a minisplit fan,
      # with an uncontrolled diffuser and no outdoor air.
      #
      # @param model [OpenStudio::Model::Model] the model
      # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] the zones to serve
      # @param cooling_type [String] 'Two Speed DX AC', 'Single Speed DX AC', or 'Single Speed Heat Pump'
      # @param heating_type [String] 'Single Speed DX'
      # @param hvac_op_sch [OpenStudio::Model::Schedule, nil] HVAC operating schedule (defaults to always on)
      # @return [Array<OpenStudio::Model::AirLoopHVAC>] the created air loops
      def self.minisplit_hp(model, thermal_zones,
                            cooling_type: 'Two Speed DX AC',
                            heating_type: 'Single Speed DX',
                            hvac_op_sch: nil)
        op_sch = hvac_op_sch ? hvac_op_sch.name.get : 'AlwaysOn'

        air_specs = []
        zone_specs = []
        thermal_zones.each do |zone|
          loop_name = "#{zone.name} Minisplit Heat Pump"
          air_specs << {
            name: loop_name,
            design_info: { use_standard_sizing: true, des_heat_sat_f: 122.0, sizing_option: 'NonCoincident' },
            availability: { schedule_name: op_sch },
            supply_components: [minisplit_unitary_spec(loop_name, zone.name.to_s, op_sch, cooling_type, heating_type)]
          }
          zone_specs << {
            zone_name: zone.name.to_s, air_loop_name: loop_name,
            air_terminal_info: { air_terminal_type: 'AirTerminalSingleDuctConstantVolumeNoReheat', name: " #{zone.name} Direct Air" }
          }
        end

        context = OpenstudioStandards::HVAC.apply_hvac(model, { air_system_info: air_specs, zone_info: zone_specs })
        air_specs.map { |spec| context.air_loop(spec[:name]) }
      end

      # The minisplit unitary system spec: a minisplit fan, a DX cooling coil, a residential-minisplit
      # DX heating coil, and an electric backup coil, in a blow-through unitary.
      #
      # @return [Hash] the AirLoopHVACUnitarySystem component spec
      def self.minisplit_unitary_spec(loop_name, zone_name, op_sch, cooling_type, heating_type)
        components = [
          { obj_type: 'FanOnOff', name: "#{loop_name} Fan", preset: 'Minisplit_HP_Fan', enduse_subcat: 'Minisplit HP Fans', schedule_name: op_sch },
          minisplit_cooling_coil(loop_name, cooling_type),
          minisplit_heating_coil(loop_name, heating_type),
          { obj_type: 'CoilHeatingElectric', name: "#{loop_name} Electric Backup Htg Coil", role: 'supplemental' }
        ].compact
        {
          obj_type: 'AirLoopHVACUnitarySystem', name: "#{loop_name} Unitary System",
          schedule_name: 'AlwaysOn', max_supply_air_temp_f: 200.0, supplemental_max_oat_f: 40.0, control_zone_name: zone_name,
          fan_operation: { placement: 'BlowThrough', op_mode_sch_name: 'AlwaysOff' },
          operating_airflows: { no_load_m3s: 0.0 },
          components: components
        }
      end

      # The minisplit cooling coil spec (two-speed residential-minisplit curves, single-speed Split-AC
      # curves, or single-speed Heat-Pump curves).
      #
      # @return [Hash] the cooling coil component spec
      def self.minisplit_cooling_coil(loop_name, cooling_type)
        case cooling_type
        when 'Two Speed DX AC'
          { obj_type: 'CoilCoolingDXTwoSpeed', name: "#{loop_name} 2spd DX AC Clg Coil", preset: 'Residential Minisplit HP' }
        when 'Single Speed DX AC'
          { obj_type: 'CoilCoolingDXSingleSpeed', name: "#{loop_name} 1spd DX AC Clg Coil", preset: 'Split AC' }
        when 'Single Speed Heat Pump'
          { obj_type: 'CoilCoolingDXSingleSpeed', name: "#{loop_name} 1spd DX HP Clg Coil", preset: 'Heat Pump' }
        else
          raise ArgumentError, "minisplit_hp composer does not support cooling_type '#{cooling_type}'"
        end
      end

      # The minisplit main heating coil spec: a residential-minisplit DX single-speed coil with
      # cold-climate compressor/defrost limits, or nil when the heating type is unsupported.
      #
      # @return [Hash, nil] the heating coil component spec
      def self.minisplit_heating_coil(loop_name, heating_type)
        return unless heating_type == 'Single Speed DX'

        { obj_type: 'CoilHeatingDXSingleSpeed', name: "#{loop_name} Heating Coil", preset: 'Residential Minisplit HP',
          min_oadb_compressor_f: -30.0, max_oadb_defrost_f: 40.0, crankcase_heater_capacity_w: 0.0, reset_defrost_time: true }
      end

      # Compose standalone residential energy recovery ventilators (one per zone), equivalent to
      # +model_add_residential_erv+.
      #
      # A ZoneHVACEnergyRecoveryVentilator per zone with a rotary sensible-and-latent heat exchanger
      # (exhaust-only frost control), supply and exhaust fans, and a controller, assigned first in the
      # zone load sequence. Defaults to a 55 cfm supply/exhaust flow, or a ventilation rate per unit
      # floor area when one is given.
      #
      # @param model [OpenStudio::Model::Model] the model
      # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] the zones to serve
      # @param min_oa_flow_m3_per_s_per_m2 [Double, nil] ventilation rate per unit floor area (m3/s/m2), or nil for 55 cfm
      # @return [Array<OpenStudio::Model::ZoneHVACEnergyRecoveryVentilator>] the created ERVs
      def self.residential_erv(model, thermal_zones, min_oa_flow_m3_per_s_per_m2 = nil)
        erv_names = []
        zone_specs = thermal_zones.map do |zone|
          erv_name = "#{zone.name} ERV"
          erv_names << erv_name
          equipment = {
            obj_type: 'ZoneHVACEnergyRecoveryVentilator', name: erv_name,
            controller_name: "#{zone.name} ERV Controller", high_humidity_control: false, vent_per_occupant_m3s: 0.0,
            hx: { name: "#{zone.name} ERV HX", hx_type: 'Rotary', economizer_lockout: false, sa_temp_ctrl: false,
                  frost_control_type: 'ExhaustOnly', schedule_name: 'AlwaysOn',
                  threshold_temp_c: -23.3, initial_defrost_time_fraction: 0.167, defrost_time_increase_rate: 1.44 },
            supply_fan: residential_erv_fan("#{zone.name} ERV Supply Fan", 270.64755),
            exhaust_fan: residential_erv_fan("#{zone.name} ERV Exhaust Fan", 270.64755),
            equipment_list_position: { cool_priority: 1, heat_priority: 1 }
          }
          if min_oa_flow_m3_per_s_per_m2.nil?
            equipment[:supply_flow_cfm] = 55.0
            equipment[:exhaust_flow_cfm] = 55.0
          else
            equipment[:vent_per_area_m3s_m2] = min_oa_flow_m3_per_s_per_m2
          end
          { zone_name: zone.name.to_s, zone_equipment: [equipment] }
        end

        OpenstudioStandards::HVAC.apply_hvac(model, { zone_info: zone_specs })
        erv_names.map { |name| model.getZoneHVACEnergyRecoveryVentilatorByName(name).get }
      end

      # The supply or exhaust fan spec for a residential ERV: the ERV fan preset with the residential
      # motor / total efficiency and pressure-rise overrides.
      #
      # @return [Hash] the fan component spec
      def self.residential_erv_fan(name, pressure_pa)
        { obj_type: 'FanOnOff', name: name, preset: 'ERV_Supply_Fan', fan_total_eff: 0.303158, motor_eff: 0.48, pressure_rise_override_pa: pressure_pa }
      end

      # Compose standalone residential unit ventilators (one per zone), equivalent to
      # +model_add_residential_ventilator+.
      #
      # A ZoneHVACUnitVentilator per zone (with a ventilator supply fan) assigned first in the zone load
      # sequence, plus a disconnected zone exhaust fan per zone. Defaults to a 55 cfm supply/exhaust
      # flow, or a given ventilation rate per unit floor area.
      #
      # @param model [OpenStudio::Model::Model] the model
      # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] the zones to serve
      # @param min_oa_flow_m3_per_s_per_m2 [Double, nil] ventilation flow (m3/s), or nil for 55 cfm
      # @return [Array<OpenStudio::Model::ZoneHVACUnitVentilator>] the created unit ventilators
      def self.residential_ventilator(model, thermal_zones, min_oa_flow_m3_per_s_per_m2 = nil)
        flow_m3s = min_oa_flow_m3_per_s_per_m2 || OpenStudio.convert(55.0, 'cfm', 'm^3/s').get

        uv_names = []
        zone_specs = thermal_zones.map do |zone|
          uv_name = "#{zone.name} Unit Ventilator"
          uv_names << uv_name
          {
            zone_name: zone.name.to_s,
            zone_equipment: [{
              obj_type: 'ZoneHVACUnitVentilator', name: uv_name, max_supply_airflow_m3s: flow_m3s,
              components: [{ obj_type: 'FanOnOff', name: "#{zone.name} Ventilator Supply Fan", preset: 'ERV_Supply_Fan',
                             fan_total_eff: 0.303158, motor_eff: 0.48, pressure_rise_override_pa: 233.6875 }],
              equipment_list_position: { cool_priority: 1, heat_priority: 1 }
            }]
          }
        end

        OpenstudioStandards::HVAC.apply_hvac(model, { zone_info: zone_specs })

        # The legacy method creates a disconnected zone exhaust fan per zone; reproduce it directly.
        thermal_zones.each do |zone|
          exhaust = OpenstudioStandards::HVAC.create_fan_zone_exhaust(model, fan_name: "#{zone.name} Exhaust Fan",
                                                                      fan_efficiency: 0.303158, pressure_rise: 233.6875)
          exhaust.setMaximumFlowRate(flow_m3s)
        end

        uv_names.map { |name| model.getZoneHVACUnitVentilatorByName(name).get }
      end

      # Compose direct evaporative coolers (one air loop per zone), equivalent to +model_add_evap_cooler+.
      #
      # A per-zone air loop with a direct evaporative cooler media, a cycling-fan unitary system holding
      # an always-off dummy DX coil, an outdoor air system, and a follow-outdoor-air-wetbulb supply-air
      # setpoint. Each air loop's availability is driven by an EMS program that turns the loop on only
      # when its zone has a cooling load (otherwise the loop would run continuously), all attached to a
      # single program calling manager.
      #
      # @param model [OpenStudio::Model::Model] the model
      # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] the zones to serve
      # @return [Array<OpenStudio::Model::AirLoopHVAC>] the created air loops
      def self.evap_cooler(model, thermal_zones)
        air_specs = []
        zone_specs = []
        sensors = []
        actuators = []
        programs = []
        program_names = []

        thermal_zones.each do |zone|
          zone_name_clean = zone.name.to_s.delete(':')
          loop_name = "#{zone_name_clean} Evaporative Cooler"
          avail_sch_name = "#{loop_name} Availability Sch"

          # Pre-create the plain constant availability schedule (value 1): both the air loop availability
          # and the EMS actuator target reference it by name.
          unless model.getScheduleConstantByName(avail_sch_name).is_initialized
            schedule = OpenStudio::Model::ScheduleConstant.new(model)
            schedule.setName(avail_sch_name)
            schedule.setValue(1)
          end

          sensor_name = "#{OpenstudioStandards::HVAC.ems_friendly_name(zone_name_clean)}_Clg_Load_Sensor"
          actuator_name = "#{OpenstudioStandards::HVAC.ems_friendly_name(loop_name)}_Availability_Actuator"
          program_name = "#{OpenstudioStandards::HVAC.ems_friendly_name(loop_name)}_Availability_Control"
          program_names << program_name

          sensors << { name: sensor_name, variable: 'Zone Predicted Sensible Load to Cooling Setpoint Heat Transfer Rate', keyname: zone.handle.to_s }
          actuators << { name: actuator_name, component_name: avail_sch_name, component_type: 'Schedule:Constant', control_type: 'Schedule Value' }
          programs << { name: program_name, body: "IF #{sensor_name} < 0.0\nSET #{actuator_name} = 1\nELSE\nSET #{actuator_name} = 0\nENDIF\n" }

          air_specs << {
            name: loop_name,
            design_info: { use_standard_sizing: true, des_cool_sat_f: 70.0 },
            availability: { schedule_name: avail_sch_name },
            oa_control: { controller_name: "#{loop_name} OA Controller",
                          ventilation: { min_limit_type: 'FixedMinimum', min_oa_frac_sch_name: 'AlwaysOn',
                                         controller_mv_name: "#{loop_name} Vent Controller", sys_oa_method: 'ZoneSum' },
                          economizer: { reset_min_db: true } },
            supply_components: [evap_unitary_spec(loop_name, zone.name.to_s), evap_media_spec(zone.name.to_s)],
            controls: [{ spm_type: 'FollowOutdoorAir', name: '3.0 F above OATwb', ref_temp: 'OutdoorAirWetBulb',
                         offset_temp_r: 3.0, max_setpt_f: 78.0, min_setpt_f: 70.0 }]
          }
          zone_specs << {
            zone_name: zone.name.to_s, air_loop_name: loop_name,
            air_terminal_info: { air_terminal_type: 'AirTerminalSingleDuctConstantVolumeNoReheat', name: "#{zone.name} Air Terminal" },
            zone_sizing: { clg_dsgn_airflow_method: 'DesignDay', clg_dsgn_sup_air_temp_f: 55.0 }
          }
        end

        ems_info = [{ sensors: sensors, actuators: actuators, programs: programs,
                      calling_managers: [{ name: 'EvapCoolerAvailabilityProgramCallingManager',
                                           calling_point: 'AfterPredictorAfterHVACManagers', program_names: program_names }] }]

        context = OpenstudioStandards::HVAC.apply_hvac(model, { air_system_info: air_specs, zone_info: zone_specs, ems_info: ems_info })
        air_specs.map { |spec| context.air_loop(spec[:name]) }
      end

      # The cycling-fan unitary system spec for an evaporative cooler: an evap-cooler supply fan and an
      # always-off dummy DX cooling coil (present so the unitary can cycle the fan on the air loop).
      #
      # @return [Hash] the AirLoopHVACUnitarySystem component spec
      def self.evap_unitary_spec(loop_name, zone_name)
        {
          obj_type: 'AirLoopHVACUnitarySystem', name: "#{zone_name} Evap Cooler Cycling Fan",
          control_zone_name: zone_name, max_supply_air_temp_f: 104.0,
          fan_operation: { placement: 'BlowThrough', op_mode_sch_name: 'AlwaysOff' },
          components: [
            { obj_type: 'FanOnOff', name: "#{zone_name} Evap Cooler Supply Fan", preset: 'Evap_Cooler_Supply_Fan', schedule_name: 'AlwaysOn' },
            { obj_type: 'CoilCoolingDXSingleSpeed', name: 'Dummy Always Off DX Coil', preset: 'default', schedule_name: 'AlwaysOff' }
          ]
        }
      end

      # The direct evaporative cooler media spec (90% design effectiveness, autosized air flow and pump).
      #
      # @return [Hash] the EvaporativeCoolerDirectResearchSpecial component spec
      def self.evap_media_spec(zone_name)
        { obj_type: 'EvaporativeCoolerDirectResearchSpecial', name: "#{zone_name} Evap Media",
          design_effectiveness: 0.90, water_pump_power_sizing_factor: 90.0, blowdown_concentration_ratio: 3.0,
          autosize_primary_air: true, autosize_water_pump: true }
      end

      # Compose zone-level energy recovery ventilators (one per zone), equivalent to +model_add_zone_erv+.
      #
      # A ZoneHVACEnergyRecoveryVentilator per zone with a plate sensible-and-latent heat exchanger,
      # supply and exhaust fans, and a controller, assigned first in the zone load sequence with zero
      # sequential load fractions. The ventilation rate is the zone's outdoor air requirement per unit
      # floor area, and the zone is sized to account for the DOAS with supply setpoints derived from the
      # heat exchanger's sensible effectiveness at AHRI rating conditions.
      #
      # @param model [OpenStudio::Model::Model] the model
      # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] the zones to serve
      # @return [Array<OpenStudio::Model::ZoneHVACEnergyRecoveryVentilator>] the created ERVs
      def self.zone_erv(model, thermal_zones)
        # Design supply temperatures from the heat exchanger sensible effectiveness (0.76) at the AHRI
        # 1060 rating conditions: heating 35 F OA / 70 F return, cooling 95 F OA / 75 F return.
        sensible_eff = 0.76
        low_setpoint_c = OpenStudio.convert(35.0 - (sensible_eff * (35.0 - 70.0)), 'F', 'C').get
        high_setpoint_c = OpenStudio.convert(95.0 - (sensible_eff * (95.0 - 75.0)), 'F', 'C').get

        erv_names = []
        zone_specs = thermal_zones.map do |zone|
          erv_name = "#{zone.name} ERV"
          erv_names << erv_name
          vent_per_area = OpenstudioStandards::ThermalZone.thermal_zone_get_outdoor_airflow_rate_per_area(zone)
          {
            zone_name: zone.name.to_s,
            zone_equipment: [{
              obj_type: 'ZoneHVACEnergyRecoveryVentilator', name: erv_name,
              controller_name: "#{zone.name} ERV Controller", vent_per_area_m3s_m2: vent_per_area,
              hx: { name: "#{zone.name} ERV HX", hx_type: 'Plate', economizer_lockout: false, sa_temp_ctrl: false,
                    sens_eff_heat_100: 0.76, sens_eff_heat_75: 0.81, lat_eff_heat_100: 0.68, lat_eff_heat_75: 0.73,
                    sens_eff_cool_100: 0.76, sens_eff_cool_75: 0.81, lat_eff_cool_100: 0.68, lat_eff_cool_75: 0.73 },
              supply_fan: zone_erv_fan("#{zone.name} ERV Supply Fan"),
              exhaust_fan: zone_erv_fan("#{zone.name} ERV Exhaust Fan"),
              equipment_list_position: { cool_priority: 1, heat_priority: 1, sequential_cooling_fraction: 0.0, sequential_heating_fraction: 0.0 }
            }],
            zone_sizing: { account_for_doas: true, doas_control_strategy: 'NeutralSupplyAir',
                           doas_low_setpoint_c: low_setpoint_c, doas_high_setpoint_c: high_setpoint_c }
          }
        end

        OpenstudioStandards::HVAC.apply_hvac(model, { zone_info: zone_specs })
        erv_names.map { |name| model.getZoneHVACEnergyRecoveryVentilatorByName(name).get }
      end

      # The supply or exhaust fan spec for a zone ERV: the ERV fan preset with the total efficiency
      # derived from a 0.65 impeller efficiency times the preset's 0.8 motor efficiency.
      #
      # @return [Hash] the fan component spec
      def self.zone_erv_fan(name)
        { obj_type: 'FanOnOff', name: name, preset: 'ERV_Supply_Fan', fan_total_eff: 0.52 }
      end

      # Compose a variable refrigerant flow system, equivalent to +model_add_vrf+.
      #
      # A single air-cooled VRF condensing unit (its master thermostat at the first zone) with a
      # variable-refrigerant-flow terminal in every zone. Each terminal has a cycling on/off supply fan
      # (300 Pa, 0.8 motor / 0.6 total efficiency) and, unless ventilation is requested, zero outdoor
      # air. Returns an empty array, matching the legacy method (which never populates its result).
      #
      # @param model [OpenStudio::Model::Model] the model
      # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] the zones to serve
      # @param ventilation [Boolean] supply ventilation air through the terminals
      # @return [Array] an empty array (the legacy method's return value)
      def self.vrf(model, thermal_zones, ventilation: false)
        cu_name = "#{thermal_zones.size} Zone VRF System"
        vrf_info = [{ name: cu_name, master_zone_name: thermal_zones[0].name.to_s }]

        zone_specs = thermal_zones.map do |zone|
          {
            zone_name: zone.name.to_s,
            zone_equipment: [{
              obj_type: 'ZoneHVACTerminalUnitVariableRefrigerantFlow', name: "#{zone.name} VRF Terminal Unit",
              cu_name: cu_name, availability_sch_name: 'AlwaysOn', op_mode_sch_name: 'AlwaysOff', no_ventilation: !ventilation,
              fan: { name: "#{zone.name} VRF Unit Cycling Fan", pressure_rise_pa: 300.0, motor_eff: 0.8, fan_total_eff: 0.6 }
            }],
            zone_sizing: { clg_dsgn_sup_air_temp_f: 55.0, htg_dsgn_sup_air_temp_f: 104.0 }
          }
        end

        OpenstudioStandards::HVAC.apply_hvac(model, { vrf_info: vrf_info, zone_info: zone_specs })
        [] # the legacy model_add_vrf never appends to its result array and returns it empty
      end

      # The district heating object type for the model version (the class was renamed at OpenStudio 3.7).
      #
      # @param model [OpenStudio::Model::Model] the model
      # @param fuel_type [String] the requested district fuel type
      # @return [String] the district heating obj_type
      def self.district_heating_type(model, fuel_type)
        return 'DistrictHeatingSteam' if fuel_type == 'DistrictHeatingSteam'

        model.version < OpenStudio::VersionString.new('3.7.0') ? 'DistrictHeating' : 'DistrictHeatingWater'
      end
    end
  end
end
