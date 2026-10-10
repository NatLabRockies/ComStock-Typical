module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Creator:VrfBuilder
    # Builds variable refrigerant flow condensing units from the vrf_info spec.
    #
    # A condensing unit (AirConditionerVariableRefrigerantFlow) is created and registered in the
    # context by name; variable refrigerant flow terminals (zone equipment) reference it by cu_name
    # and attach themselves to it when they are built. Condensing units are built before air systems
    # and zones so the terminals can resolve them.
    module VrfBuilder
      # Build a condensing unit from one vrfSystem spec and register it.
      #
      # @param spec [Hash] a vrfSystem spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::AirConditionerVariableRefrigerantFlow] the condensing unit
      def self.build(spec, context)
        spec = ComponentFactory.deep_symbolize(spec)
        master_zone = spec[:master_zone_name] ? context.zone(spec[:master_zone_name]) : nil
        creator_args = {
          name: spec[:name],
          heat_recovery: spec.fetch(:heat_recovery, true),
          condenser_type: spec[:condenser_type] || 'AirCooled',
          master_zone: master_zone
        }
        creator_args[:cooling_cop] = spec[:cooling_cop] if spec[:cooling_cop]
        creator_args[:heating_cop] = spec[:heating_cop] if spec[:heating_cop]
        creator_args[:priority_control_type] = spec[:priority_control_type] if spec[:priority_control_type]
        condensing_unit = OpenstudioStandards::HVAC.create_air_conditioner_variable_refrigerant_flow(context.model, **creator_args)

        apply_capacities(condensing_unit, spec)
        apply_temperatures(condensing_unit, spec)

        context.register_vrf_cu(spec[:name], condensing_unit)
        condensing_unit
      end

      # Apply rated cooling/heating capacities.
      #
      # @param condensing_unit [OpenStudio::Model::AirConditionerVariableRefrigerantFlow] the unit
      # @param spec [Hash] the vrfSystem spec
      # @return [void]
      def self.apply_capacities(condensing_unit, spec)
        cooling = Quantities.resolve(spec, 'cooling_rated_total_capacity', :capacity)
        condensing_unit.setGrossRatedTotalCoolingCapacity(cooling) unless cooling.nil?
        heating = Quantities.resolve(spec, 'heating_rated_total_capacity', :capacity)
        condensing_unit.setGrossRatedHeatingCapacity(heating) unless heating.nil?
        nil
      end

      # Apply minimum outdoor operating temperatures.
      #
      # @param condensing_unit [OpenStudio::Model::AirConditionerVariableRefrigerantFlow] the unit
      # @param spec [Hash] the vrfSystem spec
      # @return [void]
      def self.apply_temperatures(condensing_unit, spec)
        cooling = Quantities.resolve(spec, 'min_oa_temp_cooling', :temperature)
        condensing_unit.setMinimumOutdoorTemperatureinCoolingMode(cooling) unless cooling.nil?
        heating = Quantities.resolve(spec, 'min_oa_temp_heating', :temperature)
        condensing_unit.setMinimumOutdoorTemperatureinHeatingMode(heating) unless heating.nil?
        recovery = Quantities.resolve(spec, 'min_oa_temp_hr', :temperature)
        condensing_unit.setMinimumOutdoorTemperatureinHeatRecoveryMode(recovery) unless recovery.nil?
        nil
      end
    end
  end
end
