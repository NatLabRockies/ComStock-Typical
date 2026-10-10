module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Creator:PostSteps
    # Applies the deferred cross-loop passes declared on plant loops: waterside economizers,
    # two-pipe changeover conversions, and supply-water-temperature reset control.
    #
    # These features are declared on a plant loop entry (see the schema) but cross loop boundaries
    # (a waterside economizer draws on a condenser loop; a two-pipe conversion pairs a hot and a
    # chilled water loop; a zone-demand reset references thermostat-bearing zones). They are applied
    # here, after every plant loop and zone has been built, so all referenced loops and zones
    # resolve. Each wraps the corresponding library method and is a no-op when its declaration is
    # absent.
    module PostSteps
      # Apply every declared cross-loop pass in the schema's build order: waterside economizers,
      # then two-pipe conversions, then supply-water-temperature control.
      #
      # @param spec [Hash] the full creator spec (already deep-symbolized by the orchestrator)
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [void]
      def self.apply(spec, context)
        loop_specs = flatten_plant_loops(spec[:plant_loop_info] || [])
        loop_specs.each { |loop_spec| apply_waterside_economizer(loop_spec, context) if loop_spec[:waterside_economizer] }
        loop_specs.each { |loop_spec| apply_two_pipe(loop_spec, context) if loop_spec[:two_pipe] }
        loop_specs.each { |loop_spec| apply_supply_water_temperature_control(loop_spec, context) if loop_spec[:supply_water_temperature_control] }
        nil
      end

      # Flatten plant loop specs, following the secondary_loop recursion, so a nested secondary loop's
      # cross-loop declarations are applied too.
      #
      # @param loop_specs [Array<Hash>] plant loop specs
      # @return [Array<Hash>] the flattened, symbolized specs
      def self.flatten_plant_loops(loop_specs)
        loop_specs.flat_map do |raw|
          loop_spec = ComponentFactory.deep_symbolize(raw)
          [loop_spec] + (loop_spec[:secondary_loop] ? flatten_plant_loops([loop_spec[:secondary_loop]]) : [])
        end
      end

      # Add a waterside economizer to a chilled water loop, drawing on its condenser loop.
      #
      # @param loop_spec [Hash] the chilled water loop spec carrying +waterside_economizer+
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [void]
      def self.apply_waterside_economizer(loop_spec, context)
        economizer = loop_spec[:waterside_economizer]
        chilled_water_loop = context.plant_loop(loop_spec[:name])
        condenser_loop = context.plant_loop(economizer[:condenser_loop_name])
        integrated = economizer.key?(:integrated) ? economizer[:integrated] : true
        OpenstudioStandards::HVAC.model_add_waterside_economizer(context.model, chilled_water_loop, condenser_loop,
                                                                 integrated: integrated)
        nil
      end

      # Convert a hot water loop and its chilled water partner to two-pipe changeover operation.
      #
      # @param loop_spec [Hash] the hot water loop spec carrying +two_pipe+
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [void]
      def self.apply_two_pipe(loop_spec, context)
        two_pipe = loop_spec[:two_pipe]
        hot_water_loop = context.plant_loop(loop_spec[:name])
        chilled_water_loop = context.plant_loop(two_pipe[:partner_loop_name])
        lockout_c = Quantities.resolve(two_pipe, 'lockout_temperature', :temperature)
        lockout_f = lockout_c.nil? ? 65.0 : OpenStudio.convert(lockout_c, 'C', 'F').get
        OpenstudioStandards::HVAC.model_two_pipe_loop(context.model, hot_water_loop, chilled_water_loop,
                                                      control_strategy: two_pipe[:control_strategy] || 'outdoor_air_lockout',
                                                      lockout_temperature: lockout_f,
                                                      thermal_zones: zones_for(two_pipe, context))
        nil
      end

      # Add supply-water-temperature reset control to a plant loop.
      #
      # @param loop_spec [Hash] the plant loop spec carrying +supply_water_temperature_control+
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [void]
      def self.apply_supply_water_temperature_control(loop_spec, context)
        control = loop_spec[:supply_water_temperature_control]
        loop = context.plant_loop(loop_spec[:name])
        reset = control[:oat_reset] || {}
        OpenstudioStandards::HVAC.model_add_plant_supply_water_temperature_control(context.model, loop,
                                                                                   control_strategy: control[:strategy] || 'outdoor_air',
                                                                                   sp_at_oat_low: oat_reset_f(reset, 'setpoint_at_oat_low'),
                                                                                   oat_low: oat_reset_f(reset, 'oat_low'),
                                                                                   sp_at_oat_high: oat_reset_f(reset, 'setpoint_at_oat_high'),
                                                                                   oat_high: oat_reset_f(reset, 'oat_high'),
                                                                                   thermal_zones: zones_for(control, context))
        nil
      end

      # Resolve the thermal zones a zone-demand strategy references.
      #
      # @param spec [Hash] a spec carrying +zone_names+
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [Array<OpenStudio::Model::ThermalZone>] the resolved zones
      def self.zones_for(spec, context)
        (spec[:zone_names] || []).map { |name| context.zone(name) }
      end

      # Resolve an outdoor-air-reset temperature to degrees Fahrenheit, as the wrapped library
      # methods expect IP values.
      #
      # @param reset [Hash] the oat_reset spec
      # @param stem [String] the quantity stem (for example "oat_low")
      # @return [Float, nil] the temperature in degrees Fahrenheit, or nil when absent
      def self.oat_reset_f(reset, stem)
        value_c = Quantities.resolve(reset, stem, :temperature)
        value_c.nil? ? nil : OpenStudio.convert(value_c, 'C', 'F').get
      end
    end
  end
end
