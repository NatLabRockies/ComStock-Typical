module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Creator:AirLoopBuilder
    # Builds an AirLoopHVAC from a creator spec.
    #
    # System layer: it calls the component factory to build each supply/OA component disconnected,
    # then owns all connection — placing supply components in airflow order, building the outdoor
    # air system, and placing the loop setpoint managers. See the two-layer architecture in the
    # implementation plan.
    module AirLoopBuilder
      # Build an air loop and connect its components. When the spec sets +existing: true+ the entry
      # is applied to an air loop already in the model (retrofit mode) instead of building a new one.
      #
      # @param spec [Hash] an airLoop spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::AirLoopHVAC] the connected air loop
      def self.build(spec, context)
        spec = ComponentFactory.deep_symbolize(spec)
        return build_existing(spec, context) if spec[:existing]

        dual_duct = spec[:ahu_type].to_s == 'DualDuct'
        air_loop = OpenStudio::Model::AirLoopHVAC.new(context.model, dual_duct)
        air_loop.setName(spec[:name]) if spec[:name]

        apply_sizing(air_loop, spec[:design_info]) if spec[:design_info]
        place_supply_components(air_loop, spec[:supply_components] || [], context, dual_duct)
        build_oa_system(air_loop, spec, context) if spec[:oa_control] || spec[:oa_components]
        place_supply_inlet_components(air_loop, spec[:supply_inlet_components] || [], context)
        place_relief_components(air_loop, spec[:relief_components] || [], context)
        place_return_components(air_loop, spec[:return_components] || [], context)
        place_controls(air_loop, spec[:controls] || [], context)
        apply_availability(air_loop, spec[:availability], context) if spec[:availability]

        context.register_air_loop(air_loop.name.get, air_loop)
        air_loop
      end

      # Apply a retrofit entry to an air loop already present in the model, matched by name. No new
      # air loop, outdoor air system, night-cycle manager, or ducts are created — only sizing,
      # setpoint managers, and availability are (re)applied. A design quantity given as null clears
      # (autosizes) the corresponding field. SingleDuct only.
      #
      # @param spec [Hash] an airLoop spec with +existing: true+
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::AirLoopHVAC] the existing air loop
      # @raise [ArgumentError] when the spec is DualDuct (retrofit is SingleDuct only)
      def self.build_existing(spec, context)
        raise ArgumentError, "retrofit (existing: true) is SingleDuct only; '#{spec[:name]}' is DualDuct" if spec[:ahu_type].to_s == 'DualDuct'

        air_loop = context.air_loop(spec[:name])
        apply_sizing(air_loop, spec[:design_info], clear_nulls: true) if spec[:design_info]
        place_controls(air_loop, spec[:controls] || [], context)
        apply_availability(air_loop, spec[:availability], context) if spec[:availability]
        context.register_air_loop(air_loop.name.get, air_loop)
        air_loop
      end

      # Apply the SizingSystem fields the builder currently supports.
      #
      # @param air_loop [OpenStudio::Model::AirLoopHVAC] the air loop
      # @param design [Hash] the design_info spec
      # @param clear_nulls [Boolean] in retrofit mode, autosize a field whose design key is null
      # @return [void]
      def self.apply_sizing(air_loop, design, clear_nulls: false)
        return apply_standard_sizing(air_loop, design) if design[:use_standard_sizing]

        sizing = air_loop.sizingSystem
        cooling_sat = Quantities.resolve(design, 'des_cool_sat', :temperature)
        sizing.setCentralCoolingDesignSupplyAirTemperature(cooling_sat) unless cooling_sat.nil?
        heating_sat = Quantities.resolve(design, 'des_heat_sat', :temperature)
        sizing.setCentralHeatingDesignSupplyAirTemperature(heating_sat) unless heating_sat.nil?
        apply_supply_airflow(air_loop, design, clear_nulls)
        # 100% outdoor air (dedicated outdoor air system): size on the ventilation requirement and
        # deliver all outdoor air in both cooling and heating.
        if design[:all_outdoor_air]
          sizing.setTypeofLoadtoSizeOn('VentilationRequirement')
          sizing.setAllOutdoorAirinCooling(true)
          sizing.setAllOutdoorAirinHeating(true)
          sizing.setSystemOutdoorAirMethod('ZoneSum')
        end
        # Granular sizing fields (a DOAS sets these individually rather than via the all_outdoor_air
        # bundle, which would also force SystemOutdoorAirMethod to ZoneSum).
        sizing.setTypeofLoadtoSizeOn(design[:load_type]) if design[:load_type]
        sizing.setSizingOption(design[:sizing_option]) if design[:sizing_option]
        sizing.setAllOutdoorAirinCooling(true) if design[:all_oa_in_cooling]
        sizing.setAllOutdoorAirinHeating(true) if design[:all_oa_in_heating]
        ratio = design[:central_heating_max_flow_ratio]
        sizing.setCentralHeatingMaximumSystemAirFlowRatio(ratio) unless ratio.nil?
        nil
      end

      # Apply the standard air-loop SizingSystem defaults by delegating to the shared sizing helper,
      # taking preheat/precool/cooling/heating supply air temperatures from the design_info (with the
      # conventional defaults) and the minimum system airflow ratio from +min_sys_airflow_ratio+:
      # a number pins it, 'autosize' lets EnergyPlus derive it from the zones' heating design flows,
      # and a spec that says nothing keeps the conventional 0.3.
      #
      # @param air_loop [OpenStudio::Model::AirLoopHVAC] the air loop
      # @param design [Hash] the design_info spec
      # @return [void]
      def self.apply_standard_sizing(air_loop, design)
        temperatures = {
          'prehtg_dsgn_sup_air_temp_c' => Quantities.resolve(design, 'des_preheat_sat', :temperature) || OpenStudio.convert(45.0, 'F', 'C').get,
          'preclg_dsgn_sup_air_temp_c' => Quantities.resolve(design, 'des_precool_sat', :temperature) || OpenStudio.convert(55.0, 'F', 'C').get,
          'htg_dsgn_sup_air_temp_c' => Quantities.resolve(design, 'des_heat_sat', :temperature) || OpenStudio.convert(55.0, 'F', 'C').get,
          'clg_dsgn_sup_air_temp_c' => Quantities.resolve(design, 'des_cool_sat', :temperature) || OpenStudio.convert(55.0, 'F', 'C').get
        }
        ratio = design.key?(:min_sys_airflow_ratio) ? design[:min_sys_airflow_ratio] : 0.3
        sizing = OpenstudioStandards::HVAC.set_air_loop_system_sizing(air_loop, temperatures,
                                                                     minimum_system_airflow_ratio: ratio,
                                                                     sizing_option: design[:sizing_option] || 'Coincident')
        sizing.setAllOutdoorAirinCooling(true) if design[:all_oa_in_cooling]
        sizing.setAllOutdoorAirinHeating(true) if design[:all_oa_in_heating]
        nil
      end

      # Apply the design supply air flow rate, honoring the retrofit null-clears-to-autosize rule.
      #
      # @param air_loop [OpenStudio::Model::AirLoopHVAC] the air loop
      # @param design [Hash] the design_info spec
      # @param clear_nulls [Boolean] autosize when a design airflow key is present but null
      # @return [void]
      def self.apply_supply_airflow(air_loop, design, clear_nulls)
        if clear_nulls && airflow_cleared?(design)
          air_loop.autosizeDesignSupplyAirFlowRate
          return
        end
        flow = Quantities.resolve(design, 'des_supply_airflow', :air_flow)
        air_loop.setDesignSupplyAirFlowRate(flow) unless flow.nil?
        nil
      end

      # Whether the design supply airflow is explicitly cleared (a present-but-null unit key).
      #
      # @param design [Hash] the design_info spec
      # @return [Boolean] true when either airflow unit key is present with a null value
      def self.airflow_cleared?(design)
        (design.key?(:des_supply_airflow_cfm) && design[:des_supply_airflow_cfm].nil?) ||
          (design.key?(:des_supply_airflow_m3s) && design[:des_supply_airflow_m3s].nil?)
      end

      # Place the supply components in airflow order (supply inlet toward supply outlet). Each is
      # added at the supply outlet node in list order, so the first entry ends up nearest the
      # mixed-air inlet and the last nearest the discharge. On a DualDuct loop a component's +branch+
      # index selects which of the two supply outlet nodes it is placed on. Inline setpoint managers
      # are placed on the same node.
      #
      # @param air_loop [OpenStudio::Model::AirLoopHVAC] the air loop
      # @param specs [Array<Hash>] the supply component (or setpoint manager) specs
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @param dual_duct [Boolean] whether the air loop is a dual-duct loop
      # @return [void]
      def self.place_supply_components(air_loop, specs, context, dual_duct)
        specs.each do |raw|
          entry = ComponentFactory.symbolize(raw)
          node = supply_node(air_loop, entry, dual_duct)
          if entry[:spm_type]
            SetpointManagerFactory.build(entry, context).addToNode(node)
          else
            ComponentFactory.build(entry, context).addToNode(node)
          end
        end
        nil
      end

      # Place components on the supply inlet node, upstream of the outdoor air system. Run after the
      # outdoor air system is built, so each component added at the supply inlet node ends up upstream
      # of the OA mixing box (the legacy DOAS puts its exhaust fan here). Because each +addToNode+ at
      # the inlet inserts the new component as the most-upstream one, the first spec ends up nearest
      # the OA system and the last spec ends up most upstream at the very inlet.
      #
      # @param air_loop [OpenStudio::Model::AirLoopHVAC] the air loop
      # @param specs [Array<Hash>] the supply component specs
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [void]
      def self.place_supply_inlet_components(air_loop, specs, context)
        specs.each do |raw|
          ComponentFactory.build(ComponentFactory.symbolize(raw), context).addToNode(air_loop.supplyInletNode)
        end
        nil
      end

      # The supply node a component is placed on: the single supply outlet, or the DualDuct branch
      # node its +branch+ index selects.
      #
      # @param air_loop [OpenStudio::Model::AirLoopHVAC] the air loop
      # @param entry [Hash] the component spec
      # @param dual_duct [Boolean] whether the air loop is a dual-duct loop
      # @return [OpenStudio::Model::Node] the node
      def self.supply_node(air_loop, entry, dual_duct)
        return air_loop.supplyOutletNode unless dual_duct

        air_loop.supplyOutletNodes[entry[:branch] || 0]
      end

      # Place components on the relief (exhaust) air stream. Requires an outdoor air system.
      #
      # @param air_loop [OpenStudio::Model::AirLoopHVAC] the air loop
      # @param specs [Array<Hash>] the relief_components specs
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [void]
      def self.place_relief_components(air_loop, specs, context)
        place_on_stream(air_loop, specs, air_loop.reliefAirNode, 'relief_components', context)
      end

      # Place components on the return air stream. Requires an outdoor air system.
      #
      # @param air_loop [OpenStudio::Model::AirLoopHVAC] the air loop
      # @param specs [Array<Hash>] the return_components specs
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [void]
      def self.place_return_components(air_loop, specs, context)
        place_on_stream(air_loop, specs, air_loop.returnAirNode, 'return_components', context)
      end

      # Build and place a list of components on a stream node, warning when the node is absent.
      #
      # @param air_loop [OpenStudio::Model::AirLoopHVAC] the air loop
      # @param specs [Array<Hash>] the component specs
      # @param node [OpenStudio::Model::OptionalNode] the target node
      # @param label [String] the stream name, for messaging
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [void]
      def self.place_on_stream(air_loop, specs, node, label, context)
        return if specs.empty?

        unless node.is_initialized
          context.warn("#{label} on '#{air_loop.name.get}' require an outdoor air system; skipping")
          return
        end

        node = node.get
        specs.each { |raw| ComponentFactory.build(ComponentFactory.symbolize(raw), context).addToNode(node) }
        nil
      end

      # Build the outdoor air system and its controller from the spec.
      #
      # @param air_loop [OpenStudio::Model::AirLoopHVAC] the air loop
      # @param spec [Hash] the airLoop spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::AirLoopHVACOutdoorAirSystem] the outdoor air system
      def self.build_oa_system(air_loop, spec, context)
        controller = OpenStudio::Model::ControllerOutdoorAir.new(context.model)
        controller.setName((spec[:oa_control] || {})[:controller_name] || "#{air_loop.name.get} OA System Controller")
        apply_oa_control(controller, spec[:oa_control], context) if spec[:oa_control]

        oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(context.model, controller)
        oa_system.setName("#{air_loop.name.get} OA System")
        oa_system.addToNode(air_loop.supplyInletNode)
        place_oa_components(oa_system, spec[:oa_components] || [], context)
        oa_system
      end

      # Apply outdoor air controller fields (ventilation and economizer) from the oa_control spec.
      #
      # @param controller [OpenStudio::Model::ControllerOutdoorAir] the controller
      # @param oa_control [Hash] the oa_control spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [void]
      def self.apply_oa_control(controller, oa_control, context)
        ventilation = oa_control[:ventilation] || {}
        min_flow = Quantities.resolve(ventilation, 'min_oa_flow', :air_flow)
        controller.setMinimumOutdoorAirFlowRate(min_flow) unless min_flow.nil?
        max_flow = Quantities.resolve(ventilation, 'max_oa_flow', :air_flow)
        controller.setMaximumOutdoorAirFlowRate(max_flow) unless max_flow.nil?
        controller.setMinimumOutdoorAirSchedule(context.schedule(ventilation[:min_oa_sch_name])) if ventilation[:min_oa_sch_name]
        controller.setMinimumLimitType(ventilation[:min_limit_type]) if ventilation[:min_limit_type]
        if ventilation[:min_oa_frac_sch_name]
          controller.setMinimumFractionofOutdoorAirSchedule(context.schedule(ventilation[:min_oa_frac_sch_name]))
        end
        if ventilation[:controller_mv_name] || ventilation[:sys_oa_method] || ventilation[:dcv]
          mechanical_ventilation = controller.controllerMechanicalVentilation
          mechanical_ventilation.setName(ventilation[:controller_mv_name]) if ventilation[:controller_mv_name]
          mechanical_ventilation.setSystemOutdoorAirMethod(ventilation[:sys_oa_method]) if ventilation[:sys_oa_method]
          mechanical_ventilation.setDemandControlledVentilation(true) if ventilation[:dcv]
        end

        economizer = oa_control[:economizer] || {}
        controller.setEconomizerControlType(economizer[:type]) if economizer[:type]
        max_db = Quantities.resolve(economizer, 'max_db', :temperature)
        controller.setEconomizerMaximumLimitDryBulbTemperature(max_db) unless max_db.nil?
        min_db = Quantities.resolve(economizer, 'min_db', :temperature)
        controller.setEconomizerMinimumLimitDryBulbTemperature(min_db) unless min_db.nil?
        controller.resetEconomizerMinimumLimitDryBulbTemperature if economizer[:reset_min_db]
        controller.resetEconomizerMaximumLimitDryBulbTemperature if economizer[:reset_max_db]
        controller.resetEconomizerMaximumLimitEnthalpy if economizer[:reset_max_enthalpy]
        controller.resetMaximumFractionofOutdoorAirSchedule if economizer[:reset_max_oa_frac_sch]
        controller.setMaximumFractionofOutdoorAirSchedule(context.schedule(economizer[:max_oa_frac_sch_name])) if economizer[:max_oa_frac_sch_name]
        controller.setHeatRecoveryBypassControlType(economizer[:heat_recovery_bypass_ctrl_type]) if economizer[:heat_recovery_bypass_ctrl_type]
        nil
      end

      # Place components on the outdoor air stream, outboard-most first.
      #
      # @param oa_system [OpenStudio::Model::AirLoopHVACOutdoorAirSystem] the outdoor air system
      # @param specs [Array<Hash>] the oa_components specs
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [void]
      def self.place_oa_components(oa_system, specs, context)
        node = oa_system.outboardOANode
        return unless node.is_initialized

        node = node.get
        specs.each { |raw| ComponentFactory.build(ComponentFactory.symbolize(raw), context).addToNode(node) }
        nil
      end

      # Build and place the supply-side setpoint managers. Each goes on its type-default node — the
      # mixed-air node for a MixedAir manager, otherwise the supply outlet — unless a +spm_node+
      # override targets a named supply component's outlet (see {SetpointManagerFactory.place}).
      #
      # @param air_loop [OpenStudio::Model::AirLoopHVAC] the air loop
      # @param specs [Array<Hash>] the controls specs
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [void]
      def self.place_controls(air_loop, specs, context)
        specs.each do |spm_spec|
          manager = SetpointManagerFactory.build(spm_spec, context)
          SetpointManagerFactory.place(manager, spm_spec, air_loop, default_control_node(air_loop, spm_spec), context)
        end
        nil
      end

      # The type-default node for a supply setpoint manager: the mixed-air node for a MixedAir
      # manager when the loop has an outdoor air system, otherwise the supply outlet node.
      #
      # @param air_loop [OpenStudio::Model::AirLoopHVAC] the air loop
      # @param spec [Hash] the setpoint manager spec
      # @return [OpenStudio::Model::Node] the node
      def self.default_control_node(air_loop, spec)
        if spec[:spm_type].to_s == 'MixedAir'
          oa_system = air_loop.airLoopHVACOutdoorAirSystem
          if oa_system.is_initialized && oa_system.get.mixedAirModelObject.is_initialized
            return oa_system.get.mixedAirModelObject.get.to_Node.get
          end
        end
        air_loop.supplyOutletNode
      end

      # Apply the availability schedule and night-cycle control.
      #
      # @param air_loop [OpenStudio::Model::AirLoopHVAC] the air loop
      # @param availability [Hash] the availability spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [void]
      def self.apply_availability(air_loop, availability, context)
        air_loop.setAvailabilitySchedule(context.schedule(availability[:schedule_name])) if availability[:schedule_name]
        night_cycle = availability[:night_cycle]
        return if night_cycle.nil?

        air_loop.setNightCycleControlType(night_cycle[:control_type]) if night_cycle[:control_type]
        if night_cycle[:run_time_s]
          manager = air_loop.availabilityManagers[0]
          manager.to_AvailabilityManagerNightCycle.get.setCyclingRunTime(night_cycle[:run_time_s]) if manager&.to_AvailabilityManagerNightCycle&.is_initialized
        end
        nil
      end
    end
  end
end
