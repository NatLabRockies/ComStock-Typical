module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Creator:SetpointManagerFactory
    # Builds setpoint managers from a creator spec.
    #
    # Like the component factory this is the component layer: a builder creates and configures a
    # setpoint manager and returns it **unplaced**. Placement on a node (the type-default node or a
    # +spm_node+ override) is owned by the system builders that call {build}.
    module SetpointManagerFactory
      # Build the setpoint manager for a spec.
      #
      # @param spec [Hash] a setpoint manager spec containing +spm_type+
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::SetpointManager] the unplaced setpoint manager
      # @raise [ArgumentError] when +spm_type+ is missing or has no registered builder
      def self.build(spec, context)
        spec = ComponentFactory.symbolize(spec)
        spm_type = spec[:spm_type]
        raise ArgumentError, 'setpoint manager spec is missing spm_type' if spm_type.nil?

        builder = SETPOINTMANAGER_BUILDERS[spm_type.to_s]
        raise ArgumentError, "no builder registered for spm_type '#{spm_type}'" if builder.nil?

        manager = builder.call(spec, context)
        manager.setName(spec[:name]) if spec[:name] && manager.respond_to?(:setName)
        manager
      end

      # Whether a builder is registered for an +spm_type+.
      #
      # @param spm_type [String] the setpoint manager type
      # @return [Boolean] true when a builder exists
      def self.registered?(spm_type)
        SETPOINTMANAGER_BUILDERS.key?(spm_type.to_s)
      end

      # @param spec [Hash] a Scheduled setpoint manager spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::SetpointManagerScheduled] the setpoint manager
      def self.build_scheduled(spec, context)
        schedule, control_variable = scheduled_setpoint(spec, context)
        manager = OpenStudio::Model::SetpointManagerScheduled.new(context.model, schedule)
        manager.setControlVariable(control_variable)
        manager
      end

      # Resolve the setpoint schedule and control variable for a Scheduled manager.
      #
      # @param spec [Hash] the spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [Array(OpenStudio::Model::Schedule, String)] the schedule and control variable
      def self.scheduled_setpoint(spec, context)
        return [context.schedule(spec[:spm_sch_name]), 'Temperature'] if spec[:spm_sch_name]

        temperature = Quantities.resolve(spec, 'spm_temp', :temperature)
        unless temperature.nil?
          schedule = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(context.model, temperature,
                                                                                     name: "SPM Temperature #{temperature.round(1)}C",
                                                                                     schedule_type_limit: 'Temperature')
          return [schedule, 'Temperature']
        end

        unless spec[:spm_hr_kgpkg].nil?
          schedule = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(context.model, spec[:spm_hr_kgpkg],
                                                                                     name: "SPM HumidityRatio #{spec[:spm_hr_kgpkg]}")
          return [schedule, spec[:ctrl_var] || 'MaximumHumidityRatio']
        end

        raise ArgumentError, 'Scheduled setpoint manager requires one of spm_sch_name, spm_temp, or spm_hr'
      end

      # @param spec [Hash] a SingleZoneReheat setpoint manager spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::SetpointManagerSingleZoneReheat] the setpoint manager
      def self.build_single_zone_reheat(spec, context)
        manager = OpenStudio::Model::SetpointManagerSingleZoneReheat.new(context.model)
        manager.setControlZone(context.zone(spec[:control_zone_name])) if spec[:control_zone_name]
        minimum = Quantities.resolve(spec, 'min_setpt', :temperature)
        manager.setMinimumSupplyAirTemperature(minimum) unless minimum.nil?
        maximum = Quantities.resolve(spec, 'max_setpt', :temperature)
        manager.setMaximumSupplyAirTemperature(maximum) unless maximum.nil?
        manager
      end

      # @return [OpenStudio::Model::SetpointManagerScheduledDualSetpoint] the setpoint manager
      def self.build_scheduled_dual(spec, context)
        manager = OpenStudio::Model::SetpointManagerScheduledDualSetpoint.new(context.model)
        if spec[:spm_hi_sch_name]
          manager.setHighSetpointSchedule(context.schedule(spec[:spm_hi_sch_name]))
        else
          high = Quantities.resolve(spec, 'spm_hi_temp', :temperature)
          manager.setHighSetpointSchedule(constant_temperature(context, high)) unless high.nil?
        end
        if spec[:spm_lo_sch_name]
          manager.setLowSetpointSchedule(context.schedule(spec[:spm_lo_sch_name]))
        else
          low = Quantities.resolve(spec, 'spm_lo_temp', :temperature)
          manager.setLowSetpointSchedule(constant_temperature(context, low)) unless low.nil?
        end
        manager
      end

      # @return [OpenStudio::Model::SetpointManagerMixedAir] the setpoint manager
      def self.build_mixed_air(spec, context)
        OpenStudio::Model::SetpointManagerMixedAir.new(context.model)
      end

      # @return [OpenStudio::Model::SetpointManagerWarmest] the setpoint manager
      def self.build_warmest(spec, context)
        manager = OpenStudio::Model::SetpointManagerWarmest.new(context.model)
        minimum = Quantities.resolve(spec, 'min_setpt', :temperature)
        manager.setMinimumSetpointTemperature(minimum) unless minimum.nil?
        maximum = Quantities.resolve(spec, 'max_setpt', :temperature)
        manager.setMaximumSetpointTemperature(maximum) unless maximum.nil?
        manager
      end

      # @return [OpenStudio::Model::SetpointManagerSingleZoneCooling] the setpoint manager
      def self.build_single_zone_cooling(spec, context)
        manager = OpenStudio::Model::SetpointManagerSingleZoneCooling.new(context.model)
        manager.setControlZone(context.zone(spec[:control_zone_name])) if spec[:control_zone_name]
        apply_single_zone_limits(manager, spec)
        manager
      end

      # @return [OpenStudio::Model::SetpointManagerSingleZoneHeating] the setpoint manager
      def self.build_single_zone_heating(spec, context)
        manager = OpenStudio::Model::SetpointManagerSingleZoneHeating.new(context.model)
        manager.setControlZone(context.zone(spec[:control_zone_name])) if spec[:control_zone_name]
        apply_single_zone_limits(manager, spec)
        manager
      end

      # @return [OpenStudio::Model::SetpointManagerOutdoorAirReset] the setpoint manager
      def self.build_outdoor_air_reset(spec, context)
        manager = OpenStudio::Model::SetpointManagerOutdoorAirReset.new(context.model)
        low_oat = Quantities.resolve(spec, 'oat_low', :temperature)
        manager.setOutdoorLowTemperature(low_oat) unless low_oat.nil?
        low_set = Quantities.resolve(spec, 'setpoint_at_oat_low', :temperature)
        manager.setSetpointatOutdoorLowTemperature(low_set) unless low_set.nil?
        high_oat = Quantities.resolve(spec, 'oat_high', :temperature)
        manager.setOutdoorHighTemperature(high_oat) unless high_oat.nil?
        high_set = Quantities.resolve(spec, 'setpoint_at_oat_high', :temperature)
        manager.setSetpointatOutdoorHighTemperature(high_set) unless high_set.nil?
        manager
      end

      # @return [OpenStudio::Model::SetpointManagerSingleZoneHumidityMinimum] the setpoint manager
      def self.build_single_zone_humidity_minimum(spec, context)
        manager = OpenStudio::Model::SetpointManagerSingleZoneHumidityMinimum.new(context.model)
        manager.setControlZone(context.zone(spec[:control_zone_name])) if spec[:control_zone_name]
        manager
      end

      # @return [OpenStudio::Model::SetpointManagerFollowOutdoorAirTemperature] the setpoint manager
      def self.build_follow_outdoor_air(spec, context)
        manager = OpenStudio::Model::SetpointManagerFollowOutdoorAirTemperature.new(context.model)
        manager.setControlVariable(spec[:ctrl_var]) if spec[:ctrl_var]
        manager.setReferenceTemperatureType(spec[:ref_temp]) if spec[:ref_temp]
        offset = Quantities.resolve(spec, 'offset_temp', :temperature_difference)
        manager.setOffsetTemperatureDifference(offset) unless offset.nil?
        maximum = Quantities.resolve(spec, 'max_setpt', :temperature)
        manager.setMaximumSetpointTemperature(maximum) unless maximum.nil?
        minimum = Quantities.resolve(spec, 'min_setpt', :temperature)
        manager.setMinimumSetpointTemperature(minimum) unless minimum.nil?
        manager
      end

      # Apply the minimum/maximum supply air temperature limits shared by the single-zone
      # cooling and heating setpoint managers.
      #
      # @param manager [OpenStudio::Model::SetpointManager] the manager
      # @param spec [Hash] the spec
      # @return [void]
      def self.apply_single_zone_limits(manager, spec)
        minimum = Quantities.resolve(spec, 'min_setpt', :temperature)
        manager.setMinimumSupplyAirTemperature(minimum) unless minimum.nil?
        maximum = Quantities.resolve(spec, 'max_setpt', :temperature)
        manager.setMaximumSupplyAirTemperature(maximum) unless maximum.nil?
        nil
      end

      # Create a constant temperature schedule.
      #
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @param value_c [Float] the temperature in degrees Celsius
      # @return [OpenStudio::Model::Schedule] the schedule
      def self.constant_temperature(context, value_c)
        OpenstudioStandards::Schedules.create_constant_schedule_ruleset(context.model, value_c,
                                                                        name: "SPM Temperature #{value_c.round(1)}C",
                                                                        schedule_type_limit: 'Temperature')
      end

      # Place a setpoint manager on its target node, honoring a +spm_node+ override.
      #
      # With no override (or the sentinel +'Supply'+) the manager goes on +default_node+ — the
      # type-default node the system builder chose. An override names a component on the loop's
      # supply side (by name first, then by IDD type); the manager is placed on that component's
      # outlet node so a spec can reset the setpoint mid-stream (for example after a preheat coil).
      #
      # @param manager [OpenStudio::Model::SetpointManager] the manager to place
      # @param spec [Hash] the setpoint manager spec (read for +spm_node+)
      # @param container [OpenStudio::Model::PlantLoop, OpenStudio::Model::AirLoopHVAC] the loop
      # @param default_node [OpenStudio::Model::Node] the node used when there is no override
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [void]
      def self.place(manager, spec, container, default_node, context)
        manager.addToNode(target_node(spec[:spm_node], container, default_node, context))
        nil
      end

      # Resolve the node a setpoint manager is placed on from a +spm_node+ override.
      #
      # @param override [String, nil] the spm_node value (component name or IDD type), or nil
      # @param container [OpenStudio::Model::PlantLoop, OpenStudio::Model::AirLoopHVAC] the loop
      # @param default_node [OpenStudio::Model::Node] the fallback node
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::Node] the node
      def self.target_node(override, container, default_node, context)
        return default_node if override.nil? || override.to_s == 'Supply'

        component = find_supply_component(override.to_s, container)
        if component.nil?
          context.warn("spm_node '#{override}' matched no component on '#{container.name.get}'; placing at the default node")
          return default_node
        end
        outlet_node(component, default_node, context, override)
      end

      # Find the supply-side component a +spm_node+ override names: by exact name, then by IDD type.
      #
      # @param override [String] the spm_node value
      # @param container [OpenStudio::Model::PlantLoop, OpenStudio::Model::AirLoopHVAC] the loop
      # @return [OpenStudio::Model::ModelObject, nil] the matched component, or nil when none match
      # @raise [ArgumentError] when the override matches more than one component
      def self.find_supply_component(override, container)
        components = container.respond_to?(:supplyComponents) ? container.supplyComponents : []

        by_name = components.select { |c| c.name.is_initialized && c.name.get == override }
        return by_name.first if by_name.size == 1
        raise ArgumentError, "spm_node '#{override}' matches #{by_name.size} components by name; name the target uniquely" if by_name.size > 1

        by_type = components.select { |c| idd_type_matches?(c, override) }
        return nil if by_type.empty?
        raise ArgumentError, "spm_node type '#{override}' matches #{by_type.size} components; name the target component instead" if by_type.size > 1

        by_type.first
      end

      # Whether a component's IDD type matches a class-name override (for example +CoilHeatingWater+
      # matching +OS_Coil_Heating_Water+), ignoring underscores and case.
      #
      # @param component [OpenStudio::Model::ModelObject] the component
      # @param override [String] the class-name override
      # @return [Boolean] true when the IDD type matches
      def self.idd_type_matches?(component, override)
        component.iddObjectType.valueName.sub(/^OS_/, '').delete('_').casecmp?(override.delete('_'))
      end

      # The outlet node of a matched component, falling back to the default node when the component
      # exposes no accessible outlet node. Components come back from +supplyComponents+ as base
      # model objects, so they are downcast to the class that carries the outlet accessor: a Node is
      # its own outlet, a StraightComponent (fans, coils, boilers) exposes +outletModelObject+, and
      # a WaterToWaterComponent (chillers, heat exchangers) exposes +supplyOutletModelObject+.
      #
      # @param component [OpenStudio::Model::ModelObject] the component
      # @param default_node [OpenStudio::Model::Node] the fallback node
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @param override [String] the spm_node value, for messaging
      # @return [OpenStudio::Model::Node] the node
      def self.outlet_node(component, default_node, context, override)
        node = component.to_Node
        return node.get if node.is_initialized

        straight = component.to_StraightComponent
        outlet = straight.get.outletModelObject if straight.is_initialized
        water = component.to_WaterToWaterComponent
        outlet ||= water.get.supplyOutletModelObject if water.is_initialized

        if outlet && outlet.is_initialized && outlet.get.to_Node.is_initialized
          return outlet.get.to_Node.get
        end

        context.warn("spm_node '#{override}' has no accessible outlet node; using the default node")
        default_node
      end

      # Registry mapping an +spm_type+ to the builder that creates it. Populated incrementally.
      SETPOINTMANAGER_BUILDERS = {
        'Scheduled' => ->(spec, context) { SetpointManagerFactory.build_scheduled(spec, context) },
        'ScheduledDual' => ->(spec, context) { SetpointManagerFactory.build_scheduled_dual(spec, context) },
        'SingleZoneReheat' => ->(spec, context) { SetpointManagerFactory.build_single_zone_reheat(spec, context) },
        'SingleZoneCooling' => ->(spec, context) { SetpointManagerFactory.build_single_zone_cooling(spec, context) },
        'SingleZoneHeating' => ->(spec, context) { SetpointManagerFactory.build_single_zone_heating(spec, context) },
        'MixedAir' => ->(spec, context) { SetpointManagerFactory.build_mixed_air(spec, context) },
        'Warmest' => ->(spec, context) { SetpointManagerFactory.build_warmest(spec, context) },
        'OutdoorAirReset' => ->(spec, context) { SetpointManagerFactory.build_outdoor_air_reset(spec, context) },
        'FollowOutdoorAir' => ->(spec, context) { SetpointManagerFactory.build_follow_outdoor_air(spec, context) },
        'SingleZoneHumidityMinimum' => ->(spec, context) { SetpointManagerFactory.build_single_zone_humidity_minimum(spec, context) }
      }.freeze
    end
  end
end
