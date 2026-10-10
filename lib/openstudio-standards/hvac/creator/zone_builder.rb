module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Creator:ZoneBuilder
    # Applies zone-level HVAC to a thermal zone from a creator spec.
    #
    # System layer: it builds the air terminal and zone equipment via the component factory
    # (disconnected), then owns the connection — attaching the terminal to the named air loop for
    # the zone, adding zone equipment to the thermal zone, and ordering the zone equipment list.
    module ZoneBuilder
      # Air terminal types this builder can create so far.
      SUPPORTED_TERMINALS = [
        'AirTerminalSingleDuctConstantVolumeNoReheat',
        'AirTerminalSingleDuctVAVNoReheat',
        'AirTerminalSingleDuctVAVReheat',
        'AirTerminalSingleDuctConstantVolumeReheat',
        'AirTerminalSingleDuctParallelPIUReheat',
        'AirTerminalSingleDuctSeriesPIUReheat'
      ].freeze

      # Apply the zone HVAC for one zone spec.
      #
      # @param spec [Hash] a zoneHvac spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::ThermalZone] the zone
      def self.build(spec, context)
        spec = ComponentFactory.deep_symbolize(spec)
        zone = context.zone(spec[:zone_name])

        attach_terminal(zone, spec, context) if spec[:air_loop_name] && spec[:air_terminal_info]
        add_zone_equipment(zone, spec[:zone_equipment] || [], context)
        apply_load_distribution(zone, spec[:load_distribution])
        apply_zone_sizing(zone, spec[:zone_sizing]) if spec[:zone_sizing]
        apply_humidistat(zone, spec[:humidistat], context) if spec[:humidistat]
        zone.setReturnPlenum(context.zone(spec[:return_plenum_name])) if spec[:return_plenum_name]

        zone
      end

      # Attach a zone control humidistat (with humidifying and/or dehumidifying relative-humidity
      # setpoint schedules) to the zone.
      #
      # @param zone [OpenStudio::Model::ThermalZone] the zone
      # @param spec [Hash] the humidistat spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [void]
      def self.apply_humidistat(zone, spec, context)
        humidistat = OpenStudio::Model::ZoneControlHumidistat.new(context.model)
        humidistat.setHumidifyingRelativeHumiditySetpointSchedule(context.schedule(spec[:humidifying_rh_sch_name])) if spec[:humidifying_rh_sch_name]
        humidistat.setDehumidifyingRelativeHumiditySetpointSchedule(context.schedule(spec[:dehumidifying_rh_sch_name])) if spec[:dehumidifying_rh_sch_name]
        zone.setZoneControlHumidistat(humidistat)
        nil
      end

      # Build the air terminal and attach the zone to its air loop.
      #
      # @param zone [OpenStudio::Model::ThermalZone] the zone
      # @param spec [Hash] the zoneHvac spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [void]
      def self.attach_terminal(zone, spec, context)
        info = spec[:air_terminal_info]
        terminal = build_terminal(info, context)
        air_loop = context.air_loop(spec[:air_loop_name])
        air_loop.addBranchForZone(zone, terminal)
        apply_terminal_zone_control(zone, terminal, info)
        nil
      end

      # Apply the zone-list controls a terminal carries once it is attached: its cooling/heating
      # priority and its sequential cooling/heating load fractions (a DOAS terminal sets priority 1
      # and sequential fractions 0 so its ventilation air is delivered first and other zone equipment
      # sees the net load).
      #
      # @param zone [OpenStudio::Model::ThermalZone] the zone
      # @param terminal [OpenStudio::Model::StraightComponent] the attached terminal
      # @param info [Hash] the air_terminal_info spec
      # @return [void]
      def self.apply_terminal_zone_control(zone, terminal, info)
        zone.setCoolingPriority(terminal, info[:cool_priority]) if info[:cool_priority]
        zone.setHeatingPriority(terminal, info[:heat_priority]) if info[:heat_priority]
        zone.setSequentialCoolingFraction(terminal, info[:sequential_cooling_fraction]) unless info[:sequential_cooling_fraction].nil?
        zone.setSequentialHeatingFraction(terminal, info[:sequential_heating_fraction]) unless info[:sequential_heating_fraction].nil?
        # A second cooling-fraction assignment (the legacy DOAS overrides 0 with 1 when economizing);
        # the value setter creates a fresh fraction schedule each call, so both are applied in order.
        zone.setSequentialCoolingFraction(terminal, info[:sequential_cooling_fraction_override]) unless info[:sequential_cooling_fraction_override].nil?
        nil
      end

      # Build an air terminal from its spec.
      #
      # @param info [Hash] the air_terminal_info spec (with air_terminal_type)
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::StraightComponent] the air terminal
      # @raise [ArgumentError] when the terminal type is not yet supported
      def self.build_terminal(info, context)
        type = info[:air_terminal_type]
        raise ArgumentError, "air terminal type '#{type}' is not yet supported" unless SUPPORTED_TERMINALS.include?(type)

        schedule = info[:schedule_name] ? context.schedule(info[:schedule_name]) : context.model.alwaysOnDiscreteSchedule

        terminal =
          case type
          when 'AirTerminalSingleDuctConstantVolumeNoReheat'
            OpenStudio::Model::AirTerminalSingleDuctConstantVolumeNoReheat.new(context.model, schedule)
          when 'AirTerminalSingleDuctVAVNoReheat'
            apply_vav_fields(OpenStudio::Model::AirTerminalSingleDuctVAVNoReheat.new(context.model, schedule), info)
          when 'AirTerminalSingleDuctVAVReheat'
            apply_vav_fields(OpenStudio::Model::AirTerminalSingleDuctVAVReheat.new(context.model, schedule, reheat_coil(info, context)), info)
          when 'AirTerminalSingleDuctConstantVolumeReheat'
            OpenStudio::Model::AirTerminalSingleDuctConstantVolumeReheat.new(context.model, schedule, reheat_coil(info, context))
          when 'AirTerminalSingleDuctParallelPIUReheat'
            OpenStudio::Model::AirTerminalSingleDuctParallelPIUReheat.new(context.model, schedule, piu_fan(info, context), piu_coil(info, context))
          when 'AirTerminalSingleDuctSeriesPIUReheat'
            OpenStudio::Model::AirTerminalSingleDuctSeriesPIUReheat.new(context.model, schedule, piu_fan(info, context), piu_coil(info, context))
          end

        apply_terminal_common(terminal, info)
        terminal
      end

      # Build the terminal fan for a fan-powered (PIU) terminal.
      #
      # @param info [Hash] the air_terminal_info spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::ModelObject] the terminal fan
      def self.piu_fan(info, context)
        fan_spec = (info[:piu] || {})[:fan_data]
        raise ArgumentError, 'a fan-powered terminal requires piu.fan_data' if fan_spec.nil?

        ComponentFactory.build(fan_spec, context)
      end

      # Build the reheat coil for a fan-powered (PIU) terminal.
      #
      # @param info [Hash] the air_terminal_info spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::ModelObject] the reheat coil
      def self.piu_coil(info, context)
        coil_spec = (info[:piu] || {})[:coil_data]
        raise ArgumentError, 'a fan-powered terminal requires piu.coil_data' if coil_spec.nil?

        ComponentFactory.build(coil_spec, context)
      end

      # Build the reheat coil for a reheat terminal.
      #
      # @param info [Hash] the air_terminal_info spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::ModelObject] the reheat coil
      def self.reheat_coil(info, context)
        coil_spec = (info[:reheat] || {})[:coil_info]
        raise ArgumentError, 'reheat terminal requires reheat.coil_info' if coil_spec.nil?

        ComponentFactory.build(coil_spec, context)
      end

      # Apply the name and maximum air flow shared by all terminals.
      #
      # @param terminal [OpenStudio::Model::StraightComponent] the terminal
      # @param info [Hash] the air_terminal_info spec
      # @return [OpenStudio::Model::StraightComponent] the terminal
      def self.apply_terminal_common(terminal, info)
        terminal.setName(info[:name]) if info[:name]
        max_flow = Quantities.resolve(info, 'max_airflow', :air_flow)
        terminal.setMaximumAirFlowRate(max_flow) unless max_flow.nil?
        terminal
      end

      # Apply the VAV-specific fields (minimum flow fraction and, for reheat terminals, the damper
      # heating action) for a VAV terminal.
      #
      # @param terminal [OpenStudio::Model::StraightComponent] the VAV terminal
      # @param info [Hash] the air_terminal_info spec
      # @return [OpenStudio::Model::StraightComponent] the terminal
      def self.apply_vav_fields(terminal, info)
        vav = info[:vav] || {}
        terminal.setZoneMinimumAirFlowInputMethod(vav[:min_flow_input_method]) if vav[:min_flow_input_method] && terminal.respond_to?(:setZoneMinimumAirFlowInputMethod)
        terminal.setConstantMinimumAirFlowFraction(vav[:min_flow_frac]) if vav[:min_flow_frac]
        if vav[:damper_action] && terminal.respond_to?(:setDamperHeatingAction)
          terminal.setDamperHeatingAction(vav[:damper_action])
        end
        max_reheat = Quantities.resolve(vav, 'max_reheat_air_temp', :temperature)
        terminal.setMaximumReheatAirTemperature(max_reheat) if !max_reheat.nil? && terminal.respond_to?(:setMaximumReheatAirTemperature)
        if vav[:max_flow_per_area_reheat_m2] && terminal.respond_to?(:setMaximumFlowPerZoneFloorAreaDuringReheat)
          terminal.setMaximumFlowPerZoneFloorAreaDuringReheat(vav[:max_flow_per_area_reheat_m2])
        end
        if vav[:max_flow_frac_reheat] && terminal.respond_to?(:setMaximumFlowFractionDuringReheat)
          terminal.setMaximumFlowFractionDuringReheat(vav[:max_flow_frac_reheat])
        end
        terminal.setControlForOutdoorAir(true) if vav[:control_for_oa] && terminal.respond_to?(:setControlForOutdoorAir)
        terminal
      end

      # Build zone equipment and add each to the zone with its list priorities.
      #
      # @param zone [OpenStudio::Model::ThermalZone] the zone
      # @param specs [Array<Hash>] the zone_equipment specs
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [void]
      def self.add_zone_equipment(zone, specs, context)
        specs.each do |equipment_spec|
          equipment = ComponentFactory.build(equipment_spec, context)
          equipment.addToThermalZone(zone)
          apply_equipment_priorities(zone, equipment, equipment_spec[:equipment_list_position])
          # a variable-flow radiant system needs internal-source constructions on the zone floors
          apply_radiant_floor(zone, context.model) if equipment.to_ZoneHVACLowTempRadiantVarFlow.is_initialized
        end
        nil
      end

      # Assign an internal-source floor construction to the zone floor surfaces (and their adjacent
      # surfaces), so a low-temperature radiant system has radiant surfaces to condition through.
      #
      # @param zone [OpenStudio::Model::ThermalZone] the zone
      # @param model [OpenStudio::Model::Model] the model
      # @return [void]
      def self.apply_radiant_floor(zone, model)
        construction = radiant_floor_construction(model)
        zone.spaces.each do |space|
          space.surfaces.each do |surface|
            next unless surface.surfaceType == 'Floor'

            surface.setConstruction(construction)
            surface.adjacentSurface.get.setConstruction(construction) if surface.adjacentSurface.is_initialized
          end
        end
        nil
      end

      # The internal-source floor construction, created once per model and reused. The layers are
      # symmetric (concrete / source / concrete) so the same construction can be assigned to both
      # sides of an interior floor without an interzone construction mismatch.
      #
      # @param model [OpenStudio::Model::Model] the model
      # @return [OpenStudio::Model::ConstructionWithInternalSource] the construction
      def self.radiant_floor_construction(model)
        existing = model.getConstructionWithInternalSourceByName('Creator Radiant Floor Slab')
        return existing.get if existing.is_initialized

        concrete = OpenStudio::Model::StandardOpaqueMaterial.new(model, 'MediumRough', 0.1016, 2.31, 2322.0, 832.0)
        concrete.setName('Creator Radiant Concrete 4in')
        construction = OpenStudio::Model::ConstructionWithInternalSource.new([concrete, concrete])
        construction.setName('Creator Radiant Floor Slab')
        construction.setSourcePresentAfterLayerNumber(1)
        construction.setTemperatureCalculationRequestedAfterLayerNumber(1)
        construction.setTubeSpacing(0.2286)
        construction
      end

      # Apply cooling/heating priorities and sequential load fractions for a zone equipment object.
      #
      # @param zone [OpenStudio::Model::ThermalZone] the zone
      # @param equipment [OpenStudio::Model::ZoneHVACComponent] the equipment
      # @param position [Hash, nil] the equipment_list_position spec
      # @return [void]
      def self.apply_equipment_priorities(zone, equipment, position)
        return if position.nil?

        zone.setCoolingPriority(equipment, position[:cool_priority]) if position[:cool_priority]
        zone.setHeatingPriority(equipment, position[:heat_priority]) if position[:heat_priority]
        zone.setSequentialCoolingFraction(equipment, position[:sequential_cooling_fraction]) unless position[:sequential_cooling_fraction].nil?
        zone.setSequentialHeatingFraction(equipment, position[:sequential_heating_fraction]) unless position[:sequential_heating_fraction].nil?
        nil
      end

      # Apply the zone equipment list load distribution scheme when supported by the SDK.
      #
      # @param zone [OpenStudio::Model::ThermalZone] the zone
      # @param scheme [String, nil] the load distribution scheme
      # @return [void]
      def self.apply_load_distribution(zone, scheme)
        return if scheme.nil?

        zone.setLoadDistributionScheme(scheme) if zone.respond_to?(:setLoadDistributionScheme)
        nil
      end

      # Apply SizingZone fields from the zone_sizing spec.
      #
      # @param zone [OpenStudio::Model::ThermalZone] the zone
      # @param sizing_spec [Hash] the zone_sizing spec
      # @return [void]
      def self.apply_zone_sizing(zone, sizing_spec)
        sizing = zone.sizingZone
        cooling = Quantities.resolve(sizing_spec, 'clg_dsgn_sup_air_temp', :temperature)
        sizing.setZoneCoolingDesignSupplyAirTemperature(cooling) unless cooling.nil?
        heating = Quantities.resolve(sizing_spec, 'htg_dsgn_sup_air_temp', :temperature)
        sizing.setZoneHeatingDesignSupplyAirTemperature(heating) unless heating.nil?
        sizing.setZoneCoolingDesignSupplyAirHumidityRatio(sizing_spec[:clg_dsgn_sup_air_humidity_ratio]) if sizing_spec[:clg_dsgn_sup_air_humidity_ratio]
        sizing.setZoneHeatingDesignSupplyAirHumidityRatio(sizing_spec[:htg_dsgn_sup_air_humidity_ratio]) if sizing_spec[:htg_dsgn_sup_air_humidity_ratio]
        sizing.setHeatingMaximumAirFlowFraction(sizing_spec[:htg_max_airflow_fraction]) if sizing_spec[:htg_max_airflow_fraction]
        sizing.setCoolingDesignAirFlowMethod(sizing_spec[:clg_dsgn_airflow_method]) if sizing_spec[:clg_dsgn_airflow_method]
        sizing.setHeatingDesignAirFlowMethod(sizing_spec[:htg_dsgn_airflow_method]) if sizing_spec[:htg_dsgn_airflow_method]
        apply_doas_zone_sizing(sizing, sizing_spec)
        nil
      end

      # Apply the dedicated-outdoor-air-system SizingZone fields (a zone served by a DOAS accounts for
      # it in its own sizing and takes design low/high supply temperatures under a control strategy).
      #
      # @param sizing [OpenStudio::Model::SizingZone] the zone sizing object
      # @param sizing_spec [Hash] the zone_sizing spec
      # @return [void]
      def self.apply_doas_zone_sizing(sizing, sizing_spec)
        return unless sizing_spec[:account_for_doas]

        sizing.setAccountforDedicatedOutdoorAirSystem(true)
        sizing.setDedicatedOutdoorAirSystemControlStrategy(sizing_spec[:doas_control_strategy]) if sizing_spec[:doas_control_strategy]
        low = Quantities.resolve(sizing_spec, 'doas_low_setpoint', :temperature)
        sizing.setDedicatedOutdoorAirLowSetpointTemperatureforDesign(low) unless low.nil?
        high = Quantities.resolve(sizing_spec, 'doas_high_setpoint', :temperature)
        sizing.setDedicatedOutdoorAirHighSetpointTemperatureforDesign(high) unless high.nil?
        nil
      end
    end
  end
end
