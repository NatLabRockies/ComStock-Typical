require 'json'

module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Creator:ComponentFactory
    # Dispatches an HVAC creator component spec to the builder registered for its +obj_type+ and
    # applies the fields shared by every component.
    #
    # This is the component layer. A builder creates and fully configures a single OpenStudio
    # object (physical parameters, efficiencies, typed coefficient sets) from the component spec,
    # and returns it disconnected: builders never place the object on a loop, node, or zone.
    # Connection and placement are owned by the system builders (air loop, plant loop, zone),
    # which call this factory and then wire the returned objects together. Builders read the spec
    # directly rather than a translated argument list, and may create objects however is cleanest
    # rather than routing through the legacy create_* methods.
    #
    # Builders are registered in {COMPONENT_BUILDERS} (see registry.rb). Each builder is a
    # +->(spec, context)+ lambda. Common fields (+name+, +schedule_name+, +preset+) are applied by
    # this module after the builder runs, so builders do not repeat that logic.
    module ComponentFactory
      # Absolute path to the input schema, used to detect unrecognized keys at build time.
      SCHEMA_PATH = File.expand_path('../hvac_creator_schema.json', __dir__).freeze

      # Fan +obj_type+s whose +preset+ resolves through the packaged typical-fan data. The preset
      # selects the fan class (on/off, constant, or variable volume) and its packaged performance,
      # so a preset overrides the +obj_type+ dispatch.
      FAN_OBJ_TYPES = %w[FanOnOff FanConstantVolume FanVariableVolume FanSystemModel].freeze

      # +obj_type+s that consume a +preset+ (so the preset is not flagged as unresolved). Fans resolve
      # the preset in {build} (it selects the class); other listed types resolve it in their builder.
      PRESET_OBJ_TYPES = (FAN_OBJ_TYPES + %w[CoilCoolingDXSingleSpeed CoilCoolingDXTwoSpeed CoilHeatingDXSingleSpeed
                                             CoilCoolingWaterToAirHeatPump CoilHeatingWaterToAirHeatPump]).freeze

      # Build the OpenStudio object for a component spec.
      #
      # @param spec [Hash] a component spec containing +obj_type+ and type-specific fields
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::ModelObject] the created object
      # @raise [ArgumentError] when +obj_type+ is missing or has no registered builder
      def self.build(spec, context)
        spec = symbolize(spec)
        obj_type = spec[:obj_type]
        raise ArgumentError, 'component spec is missing obj_type' if obj_type.nil?

        builder = COMPONENT_BUILDERS[obj_type.to_s]
        raise ArgumentError, "no builder registered for obj_type '#{obj_type}'" if builder.nil?

        warn_unknown_keys(obj_type.to_s, spec, context)
        object = if spec[:preset] && FAN_OBJ_TYPES.include?(obj_type.to_s)
                   build_fan_preset(spec, context)
                 else
                   builder.call(spec, context)
                 end
        apply_common(object, spec, context)
        object
      end

      # Whether a builder is registered for an +obj_type+.
      #
      # @param obj_type [String] the OpenStudio class name
      # @return [Boolean] true when a builder exists
      def self.registered?(obj_type)
        COMPONENT_BUILDERS.key?(obj_type.to_s)
      end

      # Apply fields common to every component after the builder runs.
      #
      # @param object [OpenStudio::Model::ModelObject] the created object
      # @param spec [Hash] the component spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::ModelObject] the object
      def self.apply_common(object, spec, context)
        object.setName(spec[:name]) if spec[:name] && object.respond_to?(:setName)

        if spec[:schedule_name] && object.respond_to?(:setAvailabilitySchedule)
          object.setAvailabilitySchedule(context.schedule(spec[:schedule_name]))
        end

        # Connect the component's declared secondary side to the demand side of the named loop.
        # This resolves the component's own named plant reference (analogous to schedule_name); the
        # enclosing air/zone connection remains the system builders' responsibility. plant_loop_name
        # connects a water coil's water side; condenser_loop_name connects a water-cooled chiller's
        # condenser side. OpenStudio wires the correct side based on the component type.
        # Skip when the builder already connected the component (a preset water-to-air heat-pump coil
        # delegates to a shared creator that connects it), so it is not double-branched.
        if spec[:plant_loop_name] && !plant_connected?(object)
          context.plant_loop(spec[:plant_loop_name]).addDemandBranchForComponent(object)
          # A water coil's controller exists only once the coil is on a plant loop; configure it here
          # (it persists through the later air-side connection) to match the shared coil creators.
          setup_water_coil_controller(object, spec)
        end
        if spec[:condenser_loop_name]
          context.plant_loop(spec[:condenser_loop_name]).addDemandBranchForComponent(object)
        end

        if spec[:preset] && !PRESET_OBJ_TYPES.include?(spec[:obj_type].to_s)
          context.warn("preset '#{spec[:preset]}' requested for #{spec[:obj_type]} but preset resolution is not yet implemented")
        end

        object
      end

      # Whether a component is already connected to a plant loop (so it should not be branched again).
      #
      # @param object [OpenStudio::Model::ModelObject] the component
      # @return [Boolean] true when the component is already on a plant loop
      def self.plant_connected?(object)
        object.respond_to?(:plantLoop) && object.plantLoop.is_initialized
      end

      # Configure a water coil's controller after it has been connected to a plant loop, matching the
      # shared coil creators: a name derived from the coil, zero minimum actuated flow, reverse action
      # for a cooling coil, and a 0.1 convergence tolerance for a heating coil. A no-op for anything
      # that is not a water coil.
      #
      # @param object [OpenStudio::Model::ModelObject] the just-connected component
      # @param spec [Hash] the component spec (an optional controller_convergence_tolerance overrides
      #   the heating-coil default of 0.1)
      # @return [void]
      def self.setup_water_coil_controller(object, spec = {})
        cooling = object.to_CoilCoolingWater
        heating = object.to_CoilHeatingWater
        optional = cooling.is_initialized ? cooling.get.controllerWaterCoil : (heating.is_initialized ? heating.get.controllerWaterCoil : nil)
        return unless optional&.is_initialized

        controller = optional.get
        controller.setName("#{object.name.get} Controller")
        controller.setMinimumActuatedFlow(0.0)
        if cooling.is_initialized
          controller.setAction('Reverse')
        else
          controller.setControllerConvergenceTolerance(spec[:controller_convergence_tolerance] || 0.1)
        end
        nil
      end

      # Build a fan from a packaged typical-fan preset, reusing the shared typical-fan creator. The
      # preset determines the fan class and its packaged efficiency, pressure rise, motor efficiency,
      # and (for variable-volume fans) power curve.
      #
      # @param spec [Hash] a fan spec carrying +preset+
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::ModelObject] the fan
      # @raise [ArgumentError] when the preset is not found in the packaged fan data
      def self.build_fan_preset(spec, context)
        fan = OpenstudioStandards::HVAC.create_typical_fan(context.model, spec[:preset],
                                                          fan_name: spec[:name],
                                                          fan_efficiency: spec[:fan_total_eff],
                                                          pressure_rise: spec[:pressure_rise_inh2o],
                                                          motor_efficiency: spec[:motor_eff],
                                                          end_use_subcategory: spec[:enduse_subcat])
        raise ArgumentError, "unknown fan preset '#{spec[:preset]}'" if fan.nil?

        # create_typical_fan ignores its pressure_rise argument for non-exhaust fans; an explicit
        # override sets the pressure rise directly afterward, as the legacy DOAS exhaust fan does.
        fan.setPressureRise(OpenStudio.convert(spec[:pressure_rise_override_inh2o], 'inH_{2}O', 'Pa').get) if spec[:pressure_rise_override_inh2o]
        fan.setPressureRise(spec[:pressure_rise_override_pa]) if spec[:pressure_rise_override_pa]
        # The packaged preset carries no flow rate, so an explicit maximum is applied here the same
        # way {apply_fan_fields} applies it to a bare fan.
        max_flow = Quantities.resolve(spec, 'max_airflow', :air_flow)
        fan.setMaximumFlowRate(max_flow) unless max_flow.nil?
        fan
      end

      # Warn about keys in the spec that the schema does not declare for this +obj_type+.
      #
      # @param obj_type [String] the OpenStudio class name
      # @param spec [Hash] the component spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [void]
      def self.warn_unknown_keys(obj_type, spec, context)
        allowed = allowed_keys_for(obj_type)
        return if allowed.nil?

        spec.each_key do |key|
          next if allowed.include?(key.to_s)

          context.warn("unrecognized key '#{key}' for #{obj_type}")
        end
        nil
      end

      # The set of keys the schema declares for a component +obj_type+ (base fields plus the
      # fields of the type-specific conditional branch and any shared sub-objects it mixes in).
      #
      # @param obj_type [String] the OpenStudio class name
      # @return [Array<String>, nil] the allowed key names, or nil when the schema is unavailable
      def self.allowed_keys_for(obj_type)
        idx = schema_key_index
        return nil if idx.nil?

        idx[obj_type]
      end

      # @return [Hash{String=>Array<String>}, nil] allowed keys per obj_type, memoized
      def self.schema_key_index
        return @schema_key_index if defined?(@schema_key_index)

        @schema_key_index =
          begin
            schema = JSON.parse(File.read(SCHEMA_PATH))
            defs = schema['$defs']
            base = defs['hvacComponent']
            base_keys = base['properties'].keys
            index = {}
            (base['allOf'] || []).each do |branch|
              cond = branch.dig('if', 'properties', 'obj_type')
              next if cond.nil?

              types = cond['const'] ? [cond['const']] : (cond['enum'] || [])
              ref = branch.dig('then', '$ref')
              branch_keys = ref ? def_keys(ref, defs) : []
              types.each { |t| index[t] = (base_keys + branch_keys).uniq }
            end
            # types with no conditional branch still allow the base keys
            base['properties']['obj_type']['enum'].each { |t| index[t] ||= base_keys.dup }
            index
          rescue StandardError
            nil
          end
      end

      # Collect the property keys of a $ref-ed definition, following any allOf-referenced defs.
      #
      # @param ref [String] a "#/$defs/name" reference
      # @param defs [Hash] the schema $defs map
      # @return [Array<String>] the property keys
      def self.def_keys(ref, defs)
        name = ref.sub('#/$defs/', '')
        definition = defs[name]
        return [] if definition.nil?

        keys = (definition['properties'] || {}).keys
        (definition['allOf'] || []).each do |entry|
          keys += def_keys(entry['$ref'], defs) if entry['$ref']
        end
        keys
      end

      # Shallow-symbolize the keys of a spec hash (the orchestrator deep-symbolizes nested specs).
      #
      # @param spec [Hash] the spec
      # @return [Hash] a hash with symbol keys
      def self.symbolize(spec)
        return spec if spec.keys.all? { |k| k.is_a?(Symbol) }

        spec.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
      end

      # Recursively convert hash keys to symbols through nested hashes and arrays.
      #
      # @param object [Object] a hash, array, or scalar
      # @return [Object] the same structure with symbol keys
      def self.deep_symbolize(object)
        case object
        when Hash then object.each_with_object({}) { |(k, v), h| h[k.to_sym] = deep_symbolize(v) }
        when Array then object.map { |element| deep_symbolize(element) }
        else object
        end
      end

      # -------------------------------------------------------------------------------------
      # Builders (component layer). Each creates and configures a single OpenStudio object from
      # the spec and returns it disconnected. Name and availability schedule are applied by
      # {apply_common}; connection to loops/nodes/zones is owned by the system builders.
      # -------------------------------------------------------------------------------------

      # @param spec [Hash] a FanOnOff spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::FanOnOff] the fan
      def self.build_fan_on_off(spec, context)
        apply_fan_fields(OpenStudio::Model::FanOnOff.new(context.model), spec)
      end

      # @param spec [Hash] a FanConstantVolume spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::FanConstantVolume] the fan
      def self.build_fan_constant_volume(spec, context)
        apply_fan_fields(OpenStudio::Model::FanConstantVolume.new(context.model), spec)
      end

      # @param spec [Hash] a FanVariableVolume spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::FanVariableVolume] the fan
      def self.build_fan_variable_volume(spec, context)
        fan = apply_fan_fields(OpenStudio::Model::FanVariableVolume.new(context.model), spec)
        # A named fan curve is a typed coefficient set: the key expands to power-curve coefficients.
        OpenstudioStandards::HVAC.fan_variable_volume_set_control_type(fan, control_type: spec[:curve_type]) if spec[:curve_type]
        fan
      end

      # @param spec [Hash] a CoilHeatingGas spec (an optional +plf_curve_coeffs+ four-element cubic
      #   sets a part-load fraction correlation curve)
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::CoilHeatingGas] the coil
      def self.build_coil_heating_gas(spec, context)
        coil = OpenStudio::Model::CoilHeatingGas.new(context.model)
        efficiency = spec[:eff_percent]
        efficiency /= 100.0 if efficiency && efficiency > 1.0
        coil.setGasBurnerEfficiency(efficiency || 0.80)
        if spec[:plf_curve_coeffs]
          coeffs = spec[:plf_curve_coeffs]
          curve = OpenStudio::Model::CurveCubic.new(context.model)
          curve.setCoefficient1Constant(coeffs[0])
          curve.setCoefficient2x(coeffs[1])
          curve.setCoefficient3xPOW2(coeffs[2])
          curve.setCoefficient4xPOW3(coeffs[3])
          curve.setMinimumValueofx(spec[:plf_curve_min_x] || 0.0)
          curve.setMaximumValueofx(spec[:plf_curve_max_x] || 1.0)
          coil.setPartLoadFractionCorrelationCurve(curve)
        end
        coil
      end

      # @param spec [Hash] a CoilHeatingElectric spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::CoilHeatingElectric] the coil
      def self.build_coil_heating_electric(spec, context)
        coil = OpenStudio::Model::CoilHeatingElectric.new(context.model)
        capacity = Quantities.resolve(spec, 'capacity', :capacity)
        coil.setNominalCapacity(capacity) unless capacity.nil?
        # Written explicitly, as the shared creator does. It is also the OpenStudio default, so the
        # model behaves the same either way, but a coil that leaves the field blank does not match
        # the checked-in prototype models object for object.
        coil.setEfficiency(spec[:efficiency] || 1.0)
        coil
      end

      # @param spec [Hash] a PumpVariableSpeed spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::PumpVariableSpeed] the pump
      def self.build_pump_variable_speed(spec, context)
        pump = OpenStudio::Model::PumpVariableSpeed.new(context.model)
        apply_pump_common(pump, spec)
        if spec[:plr_coeffs]
          set_pump_plr_coefficients(pump, spec[:plr_coeffs])
        elsif spec[:vsd_control_type]
          # A named control type is a typed coefficient set: the key expands to part-load curve coefficients.
          OpenstudioStandards::HVAC.pump_variable_speed_set_control_type(pump, control_type: spec[:vsd_control_type])
        end
        pump.setFractionofMotorInefficienciestoFluidStream(spec[:frac_motor_to_fluid]) if spec[:frac_motor_to_fluid]
        pump
      end

      # @param spec [Hash] a PumpConstantSpeed spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::PumpConstantSpeed] the pump
      def self.build_pump_constant_speed(spec, context)
        apply_pump_common(OpenStudio::Model::PumpConstantSpeed.new(context.model), spec)
      end

      # @param spec [Hash] a BoilerHotWater spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::BoilerHotWater] the boiler
      def self.build_boiler_hot_water(spec, context)
        # Reuse the shared boiler creator for its scalar defaults (fuel type, efficiency curve
        # evaluation variable, flow mode, temperature limits, part-load ratios); pass no loop so it
        # stays disconnected (the plant builder owns placement). The performance curves are the
        # BoilerHotWater default set either way.
        eval_var = spec[:eff_curve_temp_eval_var]
        eval_var ||= 'EnteringBoiler' if spec[:type] == 'Condensing'
        boiler = OpenstudioStandards::HVAC.create_boiler_hot_water(
          context.model,
          hot_water_loop: nil,
          name: spec[:name],
          fuel_type: spec[:fuel_type] || 'NaturalGas',
          draft_type: spec[:draft_type] || 'Natural',
          nominal_thermal_efficiency: spec[:eff] || 0.80,
          eff_curve_temp_eval_var: eval_var || 'LeavingBoiler',
          flow_mode: spec[:flow_mode] || 'LeavingSetpointModulated',
          lvg_temp_dsgn_f: leaving_temp_f(spec),
          out_temp_lmt_f: outlet_limit_f(spec),
          min_plr: spec[:min_plr] || 0.0,
          max_plr: spec[:max_plr] || 1.2,
          opt_plr: spec[:opt_plr] || 1.0,
          sizing_factor: spec[:sizing_factor]
        )
        capacity = Quantities.resolve(spec, 'capacity', :capacity)
        boiler.setNominalCapacity(capacity) unless capacity.nil?
        flow = Quantities.resolve(spec, 'water_flow', :water_flow)
        boiler.setDesignWaterFlowRate(flow) unless flow.nil?
        boiler
      end

      # Resolve a boiler's design leaving water temperature (F), defaulting to 180 F.
      #
      # @param spec [Hash] a BoilerHotWater spec
      # @return [Float] the design leaving water temperature in degrees Fahrenheit
      def self.leaving_temp_f(spec)
        value_c = Quantities.resolve(spec, 'leaving_temp_design', :temperature)
        value_c.nil? ? 180.0 : OpenStudio.convert(value_c, 'C', 'F').get
      end

      # Resolve a boiler's water outlet upper temperature limit (F), defaulting to 203 F.
      #
      # @param spec [Hash] a BoilerHotWater spec
      # @return [Float] the water outlet upper temperature limit in degrees Fahrenheit
      def self.outlet_limit_f(spec)
        value_c = Quantities.resolve(spec, 'outlet_temp_limit', :temperature)
        value_c.nil? ? 203.0 : OpenStudio.convert(value_c, 'C', 'F').get
      end

      # @param spec [Hash] a CoilCoolingDXSingleSpeed spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::CoilCoolingDXSingleSpeed] the coil (with default performance curves)
      def self.build_coil_cooling_dx_single_speed(spec, context)
        # A preset resolves the packaged performance-curve set for the coil application (for example
        # PSZ-AC or Heat Pump) through the shared coil creator; pass no node so it stays disconnected.
        if spec[:preset]
          coil = OpenstudioStandards::HVAC.create_coil_cooling_dx_single_speed(context.model, name: spec[:name], type: spec[:preset], cop: spec[:rated_cop])
        else
          # The single-argument constructor supplies default performance curves; a named curve set
          # (curve_type) is a typed coefficient set to be resolved by the coefficient resolver.
          coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(context.model)
          coil.setRatedCOP(spec[:rated_cop]) if spec[:rated_cop]
          capacity = Quantities.resolve(spec, 'rated_capacity', :capacity)
          coil.setRatedTotalCoolingCapacity(capacity) unless capacity.nil?
          airflow = Quantities.resolve(spec, 'rated_airflow', :air_flow)
          coil.setRatedAirFlowRate(airflow) unless airflow.nil?
          min_oadb = Quantities.resolve(spec, 'min_oadb_temp', :temperature)
          coil.setMinimumOutdoorDryBulbTemperatureforCompressorOperation(min_oadb) unless min_oadb.nil?
          # Override the default total-cooling-capacity-vs-temperature curve when the spec supplies
          # one (named or user-entered) via the typed coefficient resolver.
          coil.setTotalCoolingCapacityFunctionOfTemperatureCurve(context.curve(spec[:cap_ft])) if spec[:cap_ft]
        end
        apply_dx_single_speed_cooling_overrides(coil, spec)
        coil
      end

      # Apply the optional performance/detail overrides shared by all single-speed DX cooling coils
      # (sensible heat ratio, condenser type, evaporator fan power, latent-degradation parameters,
      # and crankcase heater). Each is applied only when present so it works on preset and bare coils.
      #
      # @param coil [OpenStudio::Model::CoilCoolingDXSingleSpeed] the coil
      # @param spec [Hash] the coil spec
      # @return [void]
      def self.apply_dx_single_speed_cooling_overrides(coil, spec)
        coil.setRatedSensibleHeatRatio(spec[:sens_heat_ratio]) if spec[:sens_heat_ratio]
        coil.setCondenserType(spec[:condenser_type]) if spec[:condenser_type]
        coil.setRatedEvaporatorFanPowerPerVolumeFlowRate(spec[:evap_fan_power_w_per_m3s]) if spec[:evap_fan_power_w_per_m3s]
        coil.setNominalTimeForCondensateRemovalToBegin(spec[:condensate_removal_time_s]) if spec[:condensate_removal_time_s]
        coil.setRatioOfInitialMoistureEvaporationRateAndSteadyStateLatentCapacity(spec[:moisture_evap_ratio]) if spec[:moisture_evap_ratio]
        coil.setMaximumCyclingRate(spec[:max_cycling_rate]) if spec[:max_cycling_rate]
        coil.setLatentCapacityTimeConstant(spec[:latent_capacity_time_constant_s]) if spec[:latent_capacity_time_constant_s]
        coil.setCrankcaseHeaterCapacity(spec[:crankcase_heater_capacity_w]) if spec[:crankcase_heater_capacity_w]
        crankcase_max = Quantities.resolve(spec, 'crankcase_max_oat', :temperature)
        coil.setMaximumOutdoorDryBulbTemperatureForCrankcaseHeaterOperation(crankcase_max) unless crankcase_max.nil?
        coil.setEvaporativeCondenserEffectiveness(spec[:evap_condenser_effectiveness]) if spec[:evap_condenser_effectiveness]
        basin_setpoint = Quantities.resolve(spec, 'basin_heater_setpoint', :temperature)
        coil.setBasinHeaterSetpointTemperature(basin_setpoint) unless basin_setpoint.nil?
        nil
      end

      # @param spec [Hash] a CoilCoolingDXVariableSpeed spec with a +speeds+ list
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::CoilCoolingDXVariableSpeed] the coil
      def self.build_coil_cooling_dx_variable_speed(spec, context)
        coil = OpenStudio::Model::CoilCoolingDXVariableSpeed.new(context.model)
        rated_capacity = Quantities.resolve(spec, 'rated_total_capacity', :capacity)
        rated_airflow = Quantities.resolve(spec, 'rated_airflow', :air_flow)
        min_oadb = Quantities.resolve(spec, 'min_oadb_temp', :temperature)
        coil.setMinimumOutdoorDryBulbTemperatureforCompressorOperation(min_oadb) unless min_oadb.nil?
        coil.setEnergyPartLoadFractionCurve(context.curve(spec[:plf_curve])) if spec[:plf_curve]
        coil.setBasinHeaterCapacity(spec[:basin_heater_capacity_w]) if spec[:basin_heater_capacity_w]
        basin_setpoint = Quantities.resolve(spec, 'basin_heater_setpoint', :temperature)
        coil.setBasinHeaterSetpointTemperature(basin_setpoint) unless basin_setpoint.nil?

        (spec[:speeds] || []).each do |raw|
          speed = symbolize(raw)
          data = OpenStudio::Model::CoilCoolingDXVariableSpeedSpeedData.new(context.model)
          data.setReferenceUnitGrossRatedCoolingCOP(speed[:cop]) if speed[:cop]
          data.setReferenceUnitGrossRatedSensibleHeatRatio(speed[:shr]) if speed[:shr]
          capacity = speed[:capacity_w] || (speed[:capacity_frac] && rated_capacity ? speed[:capacity_frac] * rated_capacity : nil)
          data.setReferenceUnitGrossRatedTotalCoolingCapacity(capacity) unless capacity.nil?
          flow = speed[:flow_m3s] || (speed[:flow_frac] && rated_airflow ? speed[:flow_frac] * rated_airflow : nil)
          data.setReferenceUnitRatedAirFlowRate(flow) unless flow.nil?
          apply_variable_speed_curves(data, speed[:curves], context) if speed[:curves]
          coil.addSpeed(data)
        end

        level = spec[:nominal_speed_level] || coil.speeds.size
        coil.setNominalSpeedLevel(level) if level.positive?
        coil.setGrossRatedTotalCoolingCapacityAtSelectedNominalSpeedLevel(rated_capacity) unless rated_capacity.nil?
        coil.setRatedAirFlowRateAtSelectedNominalSpeedLevel(rated_airflow) unless rated_airflow.nil?
        coil
      end

      # @param spec [Hash] a CoilCoolingDXMultiSpeed spec with a +stages+ list
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::CoilCoolingDXMultiSpeed] the coil
      def self.build_coil_cooling_dx_multi_speed(spec, context)
        coil = OpenStudio::Model::CoilCoolingDXMultiSpeed.new(context.model)
        coil.setCondenserType(spec[:condenser_type]) if spec[:condenser_type]
        coil.setFuelType(spec[:fuel_type]) if spec[:fuel_type]
        min_oadb = Quantities.resolve(spec, 'min_oadb_temp', :temperature)
        coil.setMinimumOutdoorDryBulbTemperatureforCompressorOperation(min_oadb) unless min_oadb.nil?
        coil.setApplyPartLoadFractionToSpeedsGreaterthan1(spec[:apply_plf_to_speeds_above_1]) unless spec[:apply_plf_to_speeds_above_1].nil?
        coil.setApplyLatentDegradationtoSpeedsGreaterthan1(spec[:apply_latent_degradation_above_1]) unless spec[:apply_latent_degradation_above_1].nil?
        apply_crankcase(coil, spec[:crankcase], context) if spec[:crankcase]

        (spec[:stages] || []).each do |raw|
          stage = symbolize(raw)
          data = OpenStudio::Model::CoilCoolingDXMultiSpeedStageData.new(context.model)
          data.setGrossRatedTotalCoolingCapacity(stage[:capacity_w]) if stage[:capacity_w]
          data.setGrossRatedSensibleHeatRatio(stage[:shr]) if stage[:shr]
          data.setGrossRatedCoolingCOP(stage[:cop]) if stage[:cop]
          data.setRatedAirFlowRate(stage[:flow_m3s]) if stage[:flow_m3s]
          data.setEvaporativeCondenserEffectiveness(stage[:evap_cond_effectiveness]) if stage[:evap_cond_effectiveness]
          apply_cooling_stage_curves(data, stage[:curves], context) if stage[:curves]
          coil.addStage(data)
        end
        coil
      end

      # @param spec [Hash] a CoilHeatingDXMultiSpeed spec with a +stages+ list
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::CoilHeatingDXMultiSpeed] the coil
      def self.build_coil_heating_dx_multi_speed(spec, context)
        coil = OpenStudio::Model::CoilHeatingDXMultiSpeed.new(context.model)
        coil.setFuelType(spec[:fuel_type]) if spec[:fuel_type]
        min_oadb = Quantities.resolve(spec, 'min_oadb_temp', :temperature)
        coil.setMinimumOutdoorDryBulbTemperatureforCompressorOperation(min_oadb) unless min_oadb.nil?
        coil.setApplyPartLoadFractionToSpeedsGreaterthan1(spec[:apply_plf_to_speeds_above_1]) unless spec[:apply_plf_to_speeds_above_1].nil?
        apply_crankcase(coil, spec[:crankcase], context) if spec[:crankcase]
        apply_defrost(coil, spec[:defrost], context) if spec[:defrost]

        (spec[:stages] || []).each do |raw|
          stage = symbolize(raw)
          data = OpenStudio::Model::CoilHeatingDXMultiSpeedStageData.new(context.model)
          data.setGrossRatedHeatingCapacity(stage[:capacity_w]) if stage[:capacity_w]
          data.setGrossRatedHeatingCOP(stage[:cop]) if stage[:cop]
          data.setRatedAirFlowRate(stage[:flow_m3s]) if stage[:flow_m3s]
          apply_heating_stage_curves(data, stage[:curves], context) if stage[:curves]
          coil.addStage(data)
        end
        coil
      end

      # Apply crankcase heater fields to a multi-speed DX coil.
      #
      # @param coil [OpenStudio::Model::ModelObject] the coil
      # @param crankcase [Hash] the crankcase spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [void]
      def self.apply_crankcase(coil, crankcase, context)
        crankcase = symbolize(crankcase)
        coil.setCrankcaseHeaterCapacity(crankcase[:heater_w]) if crankcase[:heater_w]
        max_oat = Quantities.resolve(crankcase, 'max_oat', :temperature)
        coil.setMaximumOutdoorDryBulbTemperatureforCrankcaseHeaterOperation(max_oat) unless max_oat.nil?
        nil
      end

      # Apply defrost fields to a heating multi-speed DX coil.
      #
      # @param coil [OpenStudio::Model::CoilHeatingDXMultiSpeed] the coil
      # @param defrost [Hash] the defrost spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [void]
      def self.apply_defrost(coil, defrost, context)
        defrost = symbolize(defrost)
        max_oat = Quantities.resolve(defrost, 'max_oat_defrost', :temperature)
        coil.setMaximumOutdoorDryBulbTemperatureforDefrostOperation(max_oat) unless max_oat.nil?
        coil.setDefrostStrategy(defrost[:strategy]) if defrost[:strategy]
        coil.setDefrostControl(defrost[:control]) if defrost[:control]
        coil.setDefrostTimePeriodFraction(defrost[:time_period_fraction]) if defrost[:time_period_fraction]
        coil.setDefrostEnergyInputRatioFunctionofTemperatureCurve(context.curve(defrost[:eir_curve])) if defrost[:eir_curve]
        nil
      end

      # Apply the per-speed curves to a variable-speed cooling speed data object.
      #
      # @param data [OpenStudio::Model::CoilCoolingDXVariableSpeedSpeedData] the speed data
      # @param curves [Hash] the curves spec (cap_ft, cap_ff, eir_ft, eir_ff)
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [void]
      def self.apply_variable_speed_curves(data, curves, context)
        curves = symbolize(curves)
        data.setTotalCoolingCapacityFunctionofTemperatureCurve(context.curve(curves[:cap_ft])) if curves[:cap_ft]
        data.setTotalCoolingCapacityFunctionofAirFlowFractionCurve(context.curve(curves[:cap_ff])) if curves[:cap_ff]
        data.setEnergyInputRatioFunctionofTemperatureCurve(context.curve(curves[:eir_ft])) if curves[:eir_ft]
        data.setEnergyInputRatioFunctionofAirFlowFractionCurve(context.curve(curves[:eir_ff])) if curves[:eir_ff]
        nil
      end

      # Apply the per-stage curves to a cooling multi-speed stage data object.
      #
      # @param data [OpenStudio::Model::CoilCoolingDXMultiSpeedStageData] the stage data
      # @param curves [Hash] the curves spec (cap_ft, cap_ff, eir_ft, eir_ff, plf_fplr)
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [void]
      def self.apply_cooling_stage_curves(data, curves, context)
        curves = symbolize(curves)
        data.setTotalCoolingCapacityFunctionofTemperatureCurve(context.curve(curves[:cap_ft])) if curves[:cap_ft]
        data.setTotalCoolingCapacityFunctionofFlowFractionCurve(context.curve(curves[:cap_ff])) if curves[:cap_ff]
        data.setEnergyInputRatioFunctionofTemperatureCurve(context.curve(curves[:eir_ft])) if curves[:eir_ft]
        data.setEnergyInputRatioFunctionofFlowFractionCurve(context.curve(curves[:eir_ff])) if curves[:eir_ff]
        data.setPartLoadFractionCorrelationCurve(context.curve(curves[:plf_fplr])) if curves[:plf_fplr]
        nil
      end

      # Apply the per-stage curves to a heating multi-speed stage data object.
      #
      # @param data [OpenStudio::Model::CoilHeatingDXMultiSpeedStageData] the stage data
      # @param curves [Hash] the curves spec (cap_ft, cap_ff, eir_ft, eir_ff, plf_fplr)
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [void]
      def self.apply_heating_stage_curves(data, curves, context)
        curves = symbolize(curves)
        data.setHeatingCapacityFunctionofTemperatureCurve(context.curve(curves[:cap_ft])) if curves[:cap_ft]
        data.setHeatingCapacityFunctionofFlowFractionCurve(context.curve(curves[:cap_ff])) if curves[:cap_ff]
        data.setEnergyInputRatioFunctionofTemperatureCurve(context.curve(curves[:eir_ft])) if curves[:eir_ft]
        data.setEnergyInputRatioFunctionofFlowFractionCurve(context.curve(curves[:eir_ff])) if curves[:eir_ff]
        data.setPartLoadFractionCorrelationCurve(context.curve(curves[:plf_fplr])) if curves[:plf_fplr]
        nil
      end

      # @param spec [Hash] an AirLoopHVACUnitarySystem spec with a +components+ list
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::AirLoopHVACUnitarySystem] the unitary system with its sub-components assigned
      def self.build_unitary_system(spec, context)
        unitary = OpenStudio::Model::AirLoopHVACUnitarySystem.new(context.model)
        assign_unitary_subcomponents(unitary, spec[:components] || [], context)

        unitary.setControlType(spec[:control_type]) if spec[:control_type]
        fan_operation = spec[:fan_operation] || {}
        unitary.setFanPlacement(fan_operation[:placement]) if fan_operation[:placement]
        unitary.setSupplyAirFanOperatingModeSchedule(context.schedule(fan_operation[:op_mode_sch_name])) if fan_operation[:op_mode_sch_name]
        unitary.setControllingZoneorThermostatLocation(context.zone(spec[:control_zone_name])) if spec[:control_zone_name]
        max_supply = Quantities.resolve(spec, 'max_supply_air_temp', :temperature)
        unitary.setMaximumSupplyAirTemperature(max_supply) unless max_supply.nil?
        supplemental_max_oat = Quantities.resolve(spec, 'supplemental_max_oat', :temperature)
        unitary.setMaximumOutdoorDryBulbTemperatureforSupplementalHeaterOperation(supplemental_max_oat) unless supplemental_max_oat.nil?
        apply_operating_airflows(unitary, spec[:operating_airflows]) if spec[:operating_airflows]
        unitary
      end

      # Build the unitary sub-components via the factory and assign each by inferred role.
      #
      # @param unitary [OpenStudio::Model::AirLoopHVACUnitarySystem] the unitary system
      # @param specs [Array<Hash>] the sub-component specs
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [void]
      def self.assign_unitary_subcomponents(unitary, specs, context)
        heating_assigned = false
        specs.each do |raw|
          sub_spec = symbolize(raw)
          object = build(sub_spec, context)
          kind = component_kind(object)
          case kind
          when :fan
            unitary.setSupplyFan(object)
          when :cooling
            unitary.setCoolingCoil(object)
          when :heating
            if sub_spec[:role] == 'supplemental' || heating_assigned
              unitary.setSupplementalHeatingCoil(object)
            else
              unitary.setHeatingCoil(object)
              heating_assigned = true
            end
          end
        end
        nil
      end

      # Classify a built object as a fan, cooling coil, heating coil, or other.
      #
      # @param object [OpenStudio::Model::ModelObject] the object
      # @return [Symbol] :fan, :cooling, :heating, or :other
      def self.component_kind(object)
        name = object.iddObjectType.valueName
        return :fan if name.include?('Fan')
        return :cooling if name.include?('Cooling')
        return :heating if name.include?('Heating')

        :other
      end

      # Apply the operating airflows to a unitary system from the spec sub-object.
      #
      # @param unitary [OpenStudio::Model::AirLoopHVACUnitarySystem] the unitary system
      # @param airflows [Hash] the operating_airflows spec
      # @return [void]
      def self.apply_operating_airflows(unitary, airflows)
        # +autosize+ sizes all three operating airflows from the design run. Left off, an airflow the
        # spec does not give keeps the unitary's 'None' method, which is a different system: it
        # supplies no air in that operating mode rather than its design flow.
        cooling = Quantities.resolve(airflows, 'cooling', :air_flow)
        if cooling.nil?
          unitary.autosizeSupplyAirFlowRateDuringCoolingOperation if airflows[:autosize]
        else
          unitary.setSupplyAirFlowRateDuringCoolingOperation(cooling)
        end
        heating = Quantities.resolve(airflows, 'heating', :air_flow)
        if heating.nil?
          unitary.autosizeSupplyAirFlowRateDuringHeatingOperation if airflows[:autosize]
        else
          unitary.setSupplyAirFlowRateDuringHeatingOperation(heating)
        end
        no_load = Quantities.resolve(airflows, 'no_load', :air_flow)
        if no_load.nil?
          unitary.autosizeSupplyAirFlowRateWhenNoCoolingorHeatingisRequired if airflows[:autosize]
        else
          unitary.setSupplyAirFlowRateWhenNoCoolingorHeatingisRequired(no_load)
        end
        nil
      end

      # @param spec [Hash] a ZoneHVACBaseboardConvectiveElectric spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::ZoneHVACBaseboardConvectiveElectric] the baseboard (unconnected)
      def self.build_baseboard_convective_electric(spec, context)
        OpenStudio::Model::ZoneHVACBaseboardConvectiveElectric.new(context.model)
      end

      # @param spec [Hash] a ZoneHVACBaseboardConvectiveWater spec (requires hot_water_loop_name;
      #   +coil_name+ names the baseboard heating coil)
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::ZoneHVACBaseboardConvectiveWater] the baseboard
      def self.build_baseboard_convective_water(spec, context)
        coil = OpenStudio::Model::CoilHeatingWaterBaseboard.new(context.model)
        coil.setName(spec[:coil_name]) if spec[:coil_name]
        context.plant_loop(spec[:hot_water_loop_name]).addDemandBranchForComponent(coil)
        OpenStudio::Model::ZoneHVACBaseboardConvectiveWater.new(context.model, context.model.alwaysOnDiscreteSchedule, coil)
      end

      # @param spec [Hash] a ZoneHVACFourPipeFanCoil spec. Either an explicit +components+ list (fan,
      #   cooling coil, heating coil) or the synthesized form (from the loop names).
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::ZoneHVACFourPipeFanCoil] the fan coil
      def self.build_four_pipe_fan_coil(spec, context)
        schedule = spec[:schedule_name] ? context.schedule(spec[:schedule_name]) : context.model.alwaysOnDiscreteSchedule
        fan, cooling, heating = fcu_subcomponents(spec, context)

        fcu = OpenStudio::Model::ZoneHVACFourPipeFanCoil.new(context.model, schedule, fan, cooling, heating)
        fcu.setCapacityControlMethod(spec[:capacity_ctrl_method]) if spec[:capacity_ctrl_method]
        max_flow = Quantities.resolve(spec, 'max_airflow', :air_flow)
        max_flow.nil? ? fcu.autosizeMaximumSupplyAirFlowRate : fcu.setMaximumSupplyAirFlowRate(max_flow)
        fcu.setMaximumOutdoorAirFlowRate(0.0) if spec[:no_ventilation]
        fcu
      end

      # Resolve a fan coil's [fan, cooling coil, heating coil] from a +components+ list or synthesized.
      #
      # @param spec [Hash] the fan coil spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [Array(OpenStudio::Model::ModelObject, OpenStudio::Model::ModelObject, OpenStudio::Model::ModelObject)] fan, cooling, heating
      def self.fcu_subcomponents(spec, context)
        return classify_zone_hvac_components(spec[:components], context) if spec[:components]

        fan = build({ obj_type: 'FanOnOff' }, context)
        cooling = build({ obj_type: 'CoilCoolingWater', plant_loop_name: spec[:chilled_water_loop_name] }, context)
        heating =
          if spec[:hot_water_loop_name]
            build({ obj_type: 'CoilHeatingWater', plant_loop_name: spec[:hot_water_loop_name] }, context)
          else
            build({ obj_type: 'CoilHeatingElectric' }, context)
          end
        [fan, cooling, heating]
      end

      # @param spec [Hash] a ZoneHVACUnitHeater spec. Either an explicit +components+ list (fan and
      #   heating coil) or the synthesized form: a constant-volume fan taking +fan_pressure_rise+ and
      #   +max_airflow+, and a heating coil from +heating_type+ (a hot-water coil when a
      #   +hot_water_loop_name+ is given and no fuel is named). +schedule_name+ sets the unit
      #   availability schedule.
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::ZoneHVACUnitHeater] the unit heater
      def self.build_unit_heater(spec, context)
        schedule = spec[:schedule_name] ? context.schedule(spec[:schedule_name]) : context.model.alwaysOnDiscreteSchedule
        fan, _cooling, heating =
          if spec[:components]
            classify_zone_hvac_components(spec[:components], context)
          else
            [build(unit_heater_fan_spec(spec), context), nil, build_zone_heating_coil(spec, context)]
          end
        unit_heater = OpenStudio::Model::ZoneHVACUnitHeater.new(context.model, schedule, fan, heating)
        unit_heater.setFanControlType(spec[:control_type]) if spec[:control_type]
        max_flow = Quantities.resolve(spec, 'max_airflow', :air_flow)
        unit_heater.setMaximumSupplyAirFlowRate(max_flow) unless max_flow.nil?
        unit_heater
      end

      # The spec for a unit heater's synthesized constant-volume fan, carrying the unit's
      # +fan_pressure_rise+ and +max_airflow+ when given.
      #
      # @param spec [Hash] the unit heater spec
      # @return [Hash] a FanConstantVolume component spec
      def self.unit_heater_fan_spec(spec)
        fan = { obj_type: 'FanConstantVolume' }
        pressure = Quantities.resolve(spec, 'fan_pressure_rise', :pressure)
        fan[:pressure_rise_pa] = pressure unless pressure.nil?
        max_flow = Quantities.resolve(spec, 'max_airflow', :air_flow)
        fan[:max_airflow_m3s] = max_flow unless max_flow.nil?
        fan
      end

      # @param spec [Hash] a ZoneHVACPackagedTerminalAirConditioner spec. Either an explicit
      #   +components+ list (a fan, a cooling coil, and a heating coil, classified by kind) fully
      #   specifying the unit, or the synthesized form (+fan_type+/+heating_type+ with default coils).
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::ZoneHVACPackagedTerminalAirConditioner] the PTAC
      def self.build_ptac(spec, context)
        fan, cooling, heating = ptac_subcomponents(spec, context)
        ptac = OpenStudio::Model::ZoneHVACPackagedTerminalAirConditioner.new(context.model, context.model.alwaysOnDiscreteSchedule, fan, heating, cooling)
        ptac.setFanPlacement(spec[:fan_placement] || 'DrawThrough')
        ptac.setSupplyAirFanOperatingModeSchedule(context.schedule(spec[:op_mode_sch_name])) if spec[:op_mode_sch_name]
        apply_zone_hvac_no_ventilation(ptac, spec)
        ptac
      end

      # Resolve a PTAC's [fan, cooling coil, heating coil] from either an explicit +components+ list
      # (classified by kind) or the synthesized +fan_type+/+heating_type+ form.
      #
      # @param spec [Hash] the PTAC spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [Array(OpenStudio::Model::ModelObject, OpenStudio::Model::ModelObject, OpenStudio::Model::ModelObject)] fan, cooling, heating
      def self.ptac_subcomponents(spec, context)
        return classify_zone_hvac_components(spec[:components], context) if spec[:components]

        fan_type = spec[:fan_type] == 'ConstantVolume' ? 'FanConstantVolume' : 'FanOnOff'
        [build({ obj_type: fan_type }, context),
         build({ obj_type: 'CoilCoolingDXSingleSpeed' }, context),
         build_zone_heating_coil(spec, context)]
      end

      # Build a list of sub-component specs and classify them into [fan, cooling coil, heating coil,
      # supplemental heating coil]. The first heating coil is the main heating coil; a later heating
      # coil, or one tagged +role: 'supplemental'+, is the supplemental coil.
      #
      # @param specs [Array<Hash>] the sub-component specs
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [Array(OpenStudio::Model::ModelObject, OpenStudio::Model::ModelObject, OpenStudio::Model::ModelObject, OpenStudio::Model::ModelObject)] fan, cooling, heating, supplemental
      def self.classify_zone_hvac_components(specs, context)
        fan = cooling = heating = supplemental = nil
        specs.each do |raw|
          sub = symbolize(raw)
          object = build(sub, context)
          case component_kind(object)
          when :fan then fan = object
          when :cooling then cooling = object
          when :heating
            if sub[:role] == 'supplemental' || heating
              supplemental = object
            else
              heating = object
            end
          end
        end
        [fan, cooling, heating, supplemental]
      end

      # Zero the outdoor air flow rates of a packaged terminal unit when it provides no ventilation.
      #
      # @param equipment [OpenStudio::Model::ModelObject] the packaged terminal unit
      # @param spec [Hash] the unit spec
      # @return [void]
      def self.apply_zone_hvac_no_ventilation(equipment, spec)
        return unless spec[:no_ventilation]

        equipment.setOutdoorAirFlowRateDuringCoolingOperation(0.0)
        equipment.setOutdoorAirFlowRateDuringHeatingOperation(0.0)
        equipment.setOutdoorAirFlowRateWhenNoCoolingorHeatingisNeeded(0.0)
        nil
      end

      # Build a zone-equipment heating coil from the spec heating_type: a hot-water coil for +Water+
      # or a district-heating type (a +hot_water_loop_name+ is then required), gas for +NaturalGas+ /
      # +Gas+, otherwise electric. With no heating_type, a hot_water_loop_name alone selects a
      # hot-water coil.
      #
      # @param spec [Hash] the zone equipment spec (heating_type, hot_water_loop_name)
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::ModelObject] the heating coil
      # @raise [ArgumentError] when a hot-water coil is requested without a hot water loop
      def self.build_zone_heating_coil(spec, context)
        heating_type = spec[:heating_type].to_s
        loop_name = spec[:hot_water_loop_name]
        water = heating_type == 'Water' || heating_type.include?('DistrictHeating') || (heating_type.empty? && loop_name)
        if water
          raise ArgumentError, "#{spec[:obj_type]} '#{spec[:name]}' asks for hot-water heat (heating_type '#{heating_type}') but names no hot_water_loop_name" unless loop_name

          build({ obj_type: 'CoilHeatingWater', plant_loop_name: loop_name }, context)
        elsif %w[NaturalGas Gas].include?(heating_type)
          build({ obj_type: 'CoilHeatingGas' }, context)
        else
          build({ obj_type: 'CoilHeatingElectric' }, context)
        end
      end

      # ---- additional air-side components ----

      # @return [OpenStudio::Model::FanSystemModel] the fan
      def self.build_fan_system_model(spec, context)
        fan = OpenStudio::Model::FanSystemModel.new(context.model)
        pressure = Quantities.resolve(spec, 'pressure_rise', :pressure)
        fan.setDesignPressureRise(pressure) unless pressure.nil?
        fan.setMotorEfficiency(spec[:motor_eff]) if spec[:motor_eff]
        fan.setSpeedControlMethod(spec[:speed_ctrl_method]) if spec[:speed_ctrl_method]
        max_flow = Quantities.resolve(spec, 'max_airflow', :air_flow)
        fan.setDesignMaximumAirFlowRate(max_flow) unless max_flow.nil?
        fan
      end

      # @return [OpenStudio::Model::FanZoneExhaust] the fan
      def self.build_fan_zone_exhaust(spec, context)
        fan = OpenStudio::Model::FanZoneExhaust.new(context.model)
        pressure = Quantities.resolve(spec, 'pressure_rise', :pressure)
        fan.setPressureRise(pressure) unless pressure.nil?
        max_flow = Quantities.resolve(spec, 'max_airflow', :air_flow)
        fan.setMaximumFlowRate(max_flow) unless max_flow.nil?
        fan.setFlowFractionSchedule(context.schedule(spec[:flow_fraction_sch_name])) if spec[:flow_fraction_sch_name]
        fan.setSystemAvailabilityManagerCouplingMode(spec[:system_availability_coupling_mode]) if spec[:system_availability_coupling_mode]
        if spec[:balanced_exhaust_fraction_sch_name]
          fan.setBalancedExhaustFractionSchedule(context.schedule(spec[:balanced_exhaust_fraction_sch_name]))
        end
        fan
      end

      # @return [OpenStudio::Model::HumidifierSteamElectric] the humidifier (rated capacity and power
      #   autosized when not given; a new humidifier autosizes capacity but not power by default)
      def self.build_humidifier_steam_electric(spec, context)
        humidifier = OpenStudio::Model::HumidifierSteamElectric.new(context.model)
        if spec[:rated_capacity_m3s]
          humidifier.setRatedCapacity(spec[:rated_capacity_m3s])
        else
          humidifier.autosizeRatedCapacity
        end
        if spec[:rated_power_w]
          humidifier.setRatedPower(spec[:rated_power_w])
        else
          humidifier.autosizeRatedPower
        end
        humidifier
      end

      # @return [OpenStudio::Model::EvaporativeCoolerDirectResearchSpecial] the cooler
      def self.build_evaporative_cooler_direct(spec, context)
        cooler = OpenStudio::Model::EvaporativeCoolerDirectResearchSpecial.new(context.model, context.model.alwaysOnDiscreteSchedule)
        cooler.setCoolerDesignEffectiveness(spec[:design_effectiveness]) if spec[:design_effectiveness]
        cooler.setRecirculatingWaterPumpPowerConsumption(spec[:water_pump_power_w]) if spec[:water_pump_power_w]
        cooler.setWaterPumpPowerSizingFactor(spec[:water_pump_power_sizing_factor]) if spec[:water_pump_power_sizing_factor]
        cooler.setBlowdownConcentrationRatio(spec[:blowdown_concentration_ratio]) if spec[:blowdown_concentration_ratio]
        cooler.autosizePrimaryAirDesignFlowRate if spec[:autosize_primary_air]
        cooler.autosizeRecirculatingWaterPumpPowerConsumption if spec[:autosize_water_pump]
        cooler
      end

      # @return [OpenStudio::Model::CoilHeatingDesuperheater] the coil
      def self.build_coil_heating_desuperheater(spec, context)
        coil = OpenStudio::Model::CoilHeatingDesuperheater.new(context.model)
        coil.setHeatReclaimRecoveryEfficiency(spec[:reclaim_eff]) if spec[:reclaim_eff]
        coil
      end

      # @param spec [Hash] a HeatExchangerAirToAirSensibleAndLatent spec. When +hx_type+ is given the
      #   heat exchanger (and its effectiveness lookup tables) is built through the shared creator so
      #   it is byte-identical; frost control, defrost timing, and availability are applied on top.
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::HeatExchangerAirToAirSensibleAndLatent] the heat exchanger
      def self.build_hx_air_to_air(spec, context)
        hx =
          if spec[:hx_type]
            OpenstudioStandards::HVAC.create_heat_exchanger_air_to_air_sensible_and_latent(
              context.model, name: spec[:name], type: spec[:hx_type],
              economizer_lockout: spec[:economizer_lockout], supply_air_outlet_temperature_control: spec[:sa_temp_ctrl],
              frost_control_type: spec[:frost_control_type],
              sensible_heating_100_eff: spec[:sens_eff_heat_100], sensible_heating_75_eff: spec[:sens_eff_heat_75],
              latent_heating_100_eff: spec[:lat_eff_heat_100], latent_heating_75_eff: spec[:lat_eff_heat_75],
              sensible_cooling_100_eff: spec[:sens_eff_cool_100], sensible_cooling_75_eff: spec[:sens_eff_cool_75],
              latent_cooling_100_eff: spec[:lat_eff_cool_100], latent_cooling_75_eff: spec[:lat_eff_cool_75]
            )
          else
            OpenStudio::Model::HeatExchangerAirToAirSensibleAndLatent.new(context.model)
          end
        nominal_flow = Quantities.resolve(spec, 'nom_flow', :air_flow)
        hx.setNominalSupplyAirFlowRate(nominal_flow) unless nominal_flow.nil?
        hx.setSupplyAirOutletTemperatureControl(spec[:sa_temp_ctrl] == true) unless spec[:sa_temp_ctrl].nil? || spec[:hx_type]
        threshold = Quantities.resolve(spec, 'threshold_temp', :temperature)
        hx.setThresholdTemperature(threshold) unless threshold.nil?
        hx.setInitialDefrostTimeFraction(spec[:initial_defrost_time_fraction]) if spec[:initial_defrost_time_fraction]
        hx.setRateofDefrostTimeFractionIncrease(spec[:defrost_time_increase_rate]) if spec[:defrost_time_increase_rate]
        hx
      end

      # ---- additional DX coils ----

      # @return [OpenStudio::Model::CoilHeatingDXSingleSpeed] the coil (default curves)
      def self.build_coil_heating_dx_single_speed(spec, context)
        # A preset resolves the named curve set through the shared coil creator (disconnected): the
        # sentinel 'default' selects that creator's default (coil-name-derived) curve set, matching
        # the legacy DOAS heat-pump coil; any other value is a curve-set type.
        if spec[:preset]
          type = spec[:preset] == 'default' ? nil : spec[:preset]
          coil = OpenstudioStandards::HVAC.create_coil_heating_dx_single_speed(context.model, name: spec[:name], type: type, cop: spec[:rated_cop] || 3.3)
          apply_dx_single_speed_heating_overrides(coil, spec)
          return coil
        end

        coil = OpenStudio::Model::CoilHeatingDXSingleSpeed.new(context.model)
        coil.setRatedCOP(spec[:rated_cop]) if spec[:rated_cop]
        capacity = Quantities.resolve(spec, 'rated_capacity', :capacity)
        coil.setRatedTotalHeatingCapacity(capacity) unless capacity.nil?
        airflow = Quantities.resolve(spec, 'rated_airflow', :air_flow)
        coil.setRatedAirFlowRate(airflow) unless airflow.nil?
        coil
      end

      # Apply the optional single-speed DX heating coil overrides (compressor/defrost operating limits,
      # crankcase heater, defrost time-period reset) a minisplit heat pump sets.
      #
      # @param coil [OpenStudio::Model::CoilHeatingDXSingleSpeed] the coil
      # @param spec [Hash] the coil spec
      # @return [void]
      def self.apply_dx_single_speed_heating_overrides(coil, spec)
        min_oadb = Quantities.resolve(spec, 'min_oadb_compressor', :temperature)
        coil.setMinimumOutdoorDryBulbTemperatureforCompressorOperation(min_oadb) unless min_oadb.nil?
        max_defrost = Quantities.resolve(spec, 'max_oadb_defrost', :temperature)
        coil.setMaximumOutdoorDryBulbTemperatureforDefrostOperation(max_defrost) unless max_defrost.nil?
        coil.setCrankcaseHeaterCapacity(spec[:crankcase_heater_capacity_w]) unless spec[:crankcase_heater_capacity_w].nil?
        coil.resetDefrostTimePeriodFraction if spec[:reset_defrost_time]
        nil
      end

      # @return [OpenStudio::Model::CoilCoolingDXTwoSpeed] the coil (default curves)
      def self.build_coil_cooling_dx_two_speed(spec, context)
        # A preset resolves the packaged curve set through the shared coil creator (disconnected); the
        # sentinel 'default' selects that creator's default (named) curve set (its type: nil path).
        if spec[:preset]
          type = spec[:preset] == 'default' ? nil : spec[:preset]
          return OpenstudioStandards::HVAC.create_coil_cooling_dx_two_speed(context.model, name: spec[:name], type: type)
        end

        coil = OpenStudio::Model::CoilCoolingDXTwoSpeed.new(context.model)
        high = Quantities.resolve(spec, 'hs_rated_capacity', :capacity)
        coil.setRatedHighSpeedTotalCoolingCapacity(high) unless high.nil?
        coil.setRatedHighSpeedCOP(spec[:hs_rated_cop]) if spec[:hs_rated_cop]
        low = Quantities.resolve(spec, 'ls_rated_capacity', :capacity)
        coil.setRatedLowSpeedTotalCoolingCapacity(low) unless low.nil?
        coil.setRatedLowSpeedCOP(spec[:ls_rated_cop]) if spec[:ls_rated_cop]
        coil
      end

      # @return [OpenStudio::Model::CoilCoolingDXTwoStageWithHumidityControlMode] the coil (default performance)
      def self.build_coil_cooling_dx_two_stage(spec, context)
        OpenStudio::Model::CoilCoolingDXTwoStageWithHumidityControlMode.new(context.model)
      end

      # ---- water-to-air heat pump coils ----

      # @return [OpenStudio::Model::ModelObject] the cooling water-to-air heat pump coil
      def self.build_coil_cooling_wahp(spec, context)
        if spec[:obj_type] == 'CoilCoolingWaterToAirHeatPumpVariableSpeed'
          return OpenStudio::Model::CoilCoolingWaterToAirHeatPumpVariableSpeedEquationFit.new(context.model)
        end

        # A preset resolves the named default curve set through the shared creator, which also connects
        # the coil's water side to the loop (apply_common then skips the connection). The 'default'
        # sentinel selects that creator's default (type: nil) curve set.
        if spec[:preset]
          type = spec[:preset] == 'default' ? nil : spec[:preset]
          loop = context.plant_loop(spec[:plant_loop_name] || spec[:condenser_loop_name])
          coil = OpenstudioStandards::HVAC.create_coil_cooling_water_to_air_heat_pump_equation_fit(context.model, loop, name: spec[:name], type: type, cop: spec[:rated_cop] || 3.4)
          return coil
        end

        coil = OpenStudio::Model::CoilCoolingWaterToAirHeatPumpEquationFit.new(context.model)
        coil.setRatedCoolingCoefficientofPerformance(spec[:rated_cop]) if spec[:rated_cop]
        total = Quantities.resolve(spec, 'cooling_cap_total', :capacity)
        coil.setRatedTotalCoolingCapacity(total) unless total.nil?
        coil
      end

      # @return [OpenStudio::Model::CoilHeatingWaterToAirHeatPumpEquationFit] the heating coil
      def self.build_coil_heating_wahp(spec, context)
        # A preset resolves the named default curve set through the shared creator, which also connects
        # the coil's water side to the loop (apply_common then skips the connection).
        if spec[:preset]
          type = spec[:preset] == 'default' ? nil : spec[:preset]
          loop = context.plant_loop(spec[:plant_loop_name] || spec[:condenser_loop_name])
          return OpenstudioStandards::HVAC.create_coil_heating_water_to_air_heat_pump_equation_fit(context.model, loop, name: spec[:name], type: type, cop: spec[:rated_cop] || 4.2)
        end

        coil = OpenStudio::Model::CoilHeatingWaterToAirHeatPumpEquationFit.new(context.model)
        coil.setRatedHeatingCoefficientofPerformance(spec[:rated_cop]) if spec[:rated_cop]
        capacity = Quantities.resolve(spec, 'heating_cap', :capacity)
        coil.setRatedHeatingCapacity(capacity) unless capacity.nil?
        coil
      end

      # @param spec [Hash] a ZoneHVACWaterToAirHeatPump spec. Either an explicit +components+ list
      #   (fan, cooling coil, heating coil, supplemental coil) or the synthesized form (from the loop name).
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::ZoneHVACWaterToAirHeatPump] the zone water-to-air heat pump
      def self.build_zone_wahp(spec, context)
        fan, cooling, heating, supplemental =
          if spec[:components]
            classify_zone_hvac_components(spec[:components], context)
          else
            loop_name = spec[:condenser_loop_name] || spec[:plant_loop_name]
            [build({ obj_type: 'FanOnOff' }, context),
             build({ obj_type: 'CoilCoolingWaterToAirHeatPump', plant_loop_name: loop_name }, context),
             build({ obj_type: 'CoilHeatingWaterToAirHeatPump', plant_loop_name: loop_name }, context),
             build({ obj_type: 'CoilHeatingElectric' }, context)]
          end
        wahp = OpenStudio::Model::ZoneHVACWaterToAirHeatPump.new(context.model, context.model.alwaysOnDiscreteSchedule, fan, heating, cooling, supplemental)
        apply_zone_hvac_no_ventilation(wahp, spec)
        wahp
      end

      # @param spec [Hash] a ZoneHVACPackagedTerminalHeatPump spec. Either an explicit +components+
      #   list (fan, cooling coil, heating coil, and supplemental heating coil) or the synthesized form.
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::ZoneHVACPackagedTerminalHeatPump] the PTHP
      def self.build_pthp(spec, context)
        fan, cooling, heating, supplemental = pthp_subcomponents(spec, context)
        pthp = OpenStudio::Model::ZoneHVACPackagedTerminalHeatPump.new(context.model, context.model.alwaysOnDiscreteSchedule, fan, heating, cooling, supplemental)
        pthp.setFanPlacement(spec[:fan_placement] || 'DrawThrough')
        pthp.setSupplyAirFanOperatingModeSchedule(context.schedule(spec[:op_mode_sch_name])) if spec[:op_mode_sch_name]
        apply_zone_hvac_no_ventilation(pthp, spec)
        pthp
      end

      # Resolve a PTHP's [fan, cooling, heating, supplemental] from a +components+ list or synthesized.
      #
      # @param spec [Hash] the PTHP spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [Array(OpenStudio::Model::ModelObject, OpenStudio::Model::ModelObject, OpenStudio::Model::ModelObject, OpenStudio::Model::ModelObject)] fan, cooling, heating, supplemental
      def self.pthp_subcomponents(spec, context)
        return classify_zone_hvac_components(spec[:components], context) if spec[:components]

        fan_type = spec[:fan_type] == 'ConstantVolume' ? 'FanConstantVolume' : 'FanOnOff'
        [build({ obj_type: fan_type }, context),
         build({ obj_type: 'CoilCoolingDXSingleSpeed' }, context),
         build({ obj_type: 'CoilHeatingDXSingleSpeed' }, context),
         build({ obj_type: 'CoilHeatingElectric' }, context)]
      end

      # ---- additional plant components ----

      # @return [OpenStudio::Model::ModelObject] the headered pumps object
      def self.build_headered_pumps(spec, context)
        pumps = spec[:obj_type] == 'HeaderedPumpsConstantSpeed' ? OpenStudio::Model::HeaderedPumpsConstantSpeed.new(context.model) : OpenStudio::Model::HeaderedPumpsVariableSpeed.new(context.model)
        pumps.setNumberofPumpsinBank(spec[:num_pumps]) if spec[:num_pumps]
        head = Quantities.resolve(spec, 'pump_head', :pump_head)
        pumps.setRatedPumpHead(head) unless head.nil?
        flow = Quantities.resolve(spec, 'pump_flow', :water_flow)
        pumps.setTotalRatedFlowRate(flow) unless flow.nil?
        pumps.setMotorEfficiency(spec[:motor_efficiency]) if spec[:motor_efficiency]
        pumps.setPumpControlType(spec[:pump_ctrl_type]) if spec[:pump_ctrl_type]
        pumps
      end

      # @return [OpenStudio::Model::CoolingTowerSingleSpeed] the cooling tower
      def self.build_cooling_tower_single_speed(spec, context)
        tower = OpenStudio::Model::CoolingTowerSingleSpeed.new(context.model)
        tower.setCellControl(spec[:cell_control]) if spec[:cell_control]
        tower.setSizingFactor(spec[:sizing_factor]) if spec[:sizing_factor]
        tower.setNumberofCells(spec[:num_cells]) if spec[:num_cells]
        tower
      end

      # @return [OpenStudio::Model::CoolingTowerTwoSpeed] the cooling tower
      def self.build_cooling_tower_two_speed(spec, context)
        tower = OpenStudio::Model::CoolingTowerTwoSpeed.new(context.model)
        tower.setSizingFactor(spec[:sizing_factor]) if spec[:sizing_factor]
        tower.setNumberofCells(spec[:num_cells]) if spec[:num_cells]
        tower
      end

      # The design flow rates autosize when the spec omits them, so a cooler carries sized flows
      # rather than the constructor's hard-coded defaults.
      #
      # @return [OpenStudio::Model::FluidCoolerSingleSpeed] the fluid cooler
      def self.build_fluid_cooler_single_speed(spec, context)
        cooler = OpenStudio::Model::FluidCoolerSingleSpeed.new(context.model)
        cooler.setPerformanceInputMethod(spec[:performance_input_method]) if spec[:performance_input_method]
        water = Quantities.resolve(spec, 'design_water_flow', :water_flow)
        water.nil? ? cooler.autosizeDesignWaterFlowRate : cooler.setDesignWaterFlowRate(water)
        air = Quantities.resolve(spec, 'design_air_flow', :air_flow)
        air.nil? ? cooler.autosizeDesignAirFlowRate : cooler.setDesignAirFlowRate(air)
        cooler
      end

      # @return [OpenStudio::Model::FluidCoolerTwoSpeed] the fluid cooler
      def self.build_fluid_cooler_two_speed(spec, context)
        cooler = OpenStudio::Model::FluidCoolerTwoSpeed.new(context.model)
        cooler.setPerformanceInputMethod(spec[:performance_input_method]) if spec[:performance_input_method]
        water = Quantities.resolve(spec, 'design_water_flow', :water_flow)
        water.nil? ? cooler.autosizeDesignWaterFlowRate : cooler.setDesignWaterFlowRate(water)
        high = Quantities.resolve(spec, 'design_high_fan_speed_air_flow', :air_flow)
        high.nil? ? cooler.autosizeHighFanSpeedAirFlowRate : cooler.setHighFanSpeedAirFlowRate(high)
        low = Quantities.resolve(spec, 'design_low_fan_speed_air_flow', :air_flow)
        low.nil? ? cooler.autosizeLowFanSpeedAirFlowRate : cooler.setLowFanSpeedAirFlowRate(low)
        cooler
      end

      # @return [OpenStudio::Model::ModelObject] the evaporative fluid cooler
      def self.build_evaporative_fluid_cooler(spec, context)
        cooler = spec[:obj_type] == 'EvaporativeFluidCoolerTwoSpeed' ? OpenStudio::Model::EvaporativeFluidCoolerTwoSpeed.new(context.model) : OpenStudio::Model::EvaporativeFluidCoolerSingleSpeed.new(context.model)
        cooler.setPerformanceInputMethod(spec[:performance_input_method]) if spec[:performance_input_method]
        spray = Quantities.resolve(spec, 'spray_water_flow', :water_flow)
        cooler.setDesignSprayWaterFlowRate(spray) unless spray.nil?
        cooler
      end

      # @return [OpenStudio::Model::HeatExchangerFluidToFluid] the heat exchanger
      def self.build_hx_fluid_to_fluid(spec, context)
        hx = OpenStudio::Model::HeatExchangerFluidToFluid.new(context.model)
        hx.setHeatExchangeModelType(spec[:hx_mode_type]) if spec[:hx_mode_type]
        hx.setControlType(spec[:control_type]) if spec[:control_type]
        hx
      end

      # @return [OpenStudio::Model::PlantComponentTemperatureSource] the temperature source
      def self.build_plant_temperature_source(spec, context)
        source = OpenStudio::Model::PlantComponentTemperatureSource.new(context.model)
        source.setTemperatureSpecificationType(spec[:temp_spec_type]) if spec[:temp_spec_type]
        temp = Quantities.resolve(spec, 'source_temp', :temperature)
        source.setSourceTemperature(temp) unless temp.nil?
        # A named source schedule is a Schedule:Constant, because the ground-heat-exchanger EMS
        # actuates it as one. It is created here if the model does not already carry it.
        if spec[:source_temp_schedule_name]
          schedule = OpenstudioStandards::Schedules.create_schedule_constant(context.model, temp || 24.0,
                                                                            name: spec[:source_temp_schedule_name])
          source.setSourceTemperatureSchedule(schedule)
        end
        source
      end

      # @return [OpenStudio::Model::ModelObject] the plant-loop EIR heat pump
      def self.build_hp_plant_loop_eir(spec, context)
        heat_pump = spec[:obj_type] == 'HeatPumpPlantLoopEIRHeating' ? OpenStudio::Model::HeatPumpPlantLoopEIRHeating.new(context.model) : OpenStudio::Model::HeatPumpPlantLoopEIRCooling.new(context.model)
        heat_pump.setReferenceCoefficientofPerformance(spec[:cop]) if spec[:cop]
        capacity = Quantities.resolve(spec, 'capacity', :capacity)
        heat_pump.setReferenceCapacity(capacity) unless capacity.nil?
        heat_pump.setCondenserType(spec[:condenser_type]) if spec[:condenser_type] && heat_pump.respond_to?(:setCondenserType)
        heat_pump
      end

      # @return [OpenStudio::Model::ModelObject] the water-to-water equation-fit heat pump
      def self.build_hp_water_to_water(spec, context)
        cooling = spec[:obj_type] == 'HeatPumpWaterToWaterEquationFitCooling'
        heat_pump = cooling ? OpenStudio::Model::HeatPumpWaterToWaterEquationFitCooling.new(context.model) : OpenStudio::Model::HeatPumpWaterToWaterEquationFitHeating.new(context.model)
        load_flow = Quantities.resolve(spec, 'ref_load_flow', :water_flow)
        heat_pump.setReferenceLoadSideFlowRate(load_flow) unless load_flow.nil?
        source_flow = Quantities.resolve(spec, 'ref_src_flow', :water_flow)
        heat_pump.setReferenceSourceSideFlowRate(source_flow) unless source_flow.nil?
        capacity = Quantities.resolve(spec, 'ref_cap', :capacity)
        unless capacity.nil?
          cooling ? heat_pump.setRatedCoolingCapacity(capacity) : heat_pump.setRatedHeatingCapacity(capacity)
        end
        heat_pump
      end

      # @return [OpenStudio::Model::ThermalStorageIceDetailed] the ice storage
      def self.build_ice_storage(spec, context)
        ice = OpenStudio::Model::ThermalStorageIceDetailed.new(context.model)
        ice.setCapacity(spec[:capacity_gj]) if spec[:capacity_gj]
        ice
      end

      # ---- additional zone equipment ----

      # @return [OpenStudio::Model::ZoneHVACIdealLoadsAirSystem] the ideal loads system
      def self.build_ideal_loads(spec, context)
        ideal = OpenStudio::Model::ZoneHVACIdealLoadsAirSystem.new(context.model)
        max_heat = Quantities.resolve(spec, 'max_heat', :temperature)
        ideal.setMaximumHeatingSupplyAirTemperature(max_heat) unless max_heat.nil?
        min_cool = Quantities.resolve(spec, 'min_cool', :temperature)
        ideal.setMinimumCoolingSupplyAirTemperature(min_cool) unless min_cool.nil?
        ideal.setAvailabilitySchedule(context.schedule(spec[:schedule_name])) if spec[:schedule_name]
        ideal.setHeatingAvailabilitySchedule(context.schedule(spec[:heat_avail_sch_name])) if spec[:heat_avail_sch_name]
        ideal.setCoolingAvailabilitySchedule(context.schedule(spec[:cool_avail_sch_name])) if spec[:cool_avail_sch_name]
        ideal.setHeatingLimit(spec[:heat_limit_type]) if spec[:heat_limit_type]
        ideal.setCoolingLimit(spec[:cool_limit_type]) if spec[:cool_limit_type]
        ideal.setDehumidificationControlType(spec[:dehumid_limit_type]) if spec[:dehumid_limit_type]
        ideal.setCoolingSensibleHeatRatio(spec[:cool_sensible_heat_ratio]) if spec[:cool_sensible_heat_ratio]
        ideal.setHumidificationControlType(spec[:humid_ctrl_type]) if spec[:humid_ctrl_type]
        ideal.setDemandControlledVentilationType(spec[:dcv_type]) if spec[:dcv_type]
        ideal.setOutdoorAirEconomizerType(spec[:econo_ctrl_mthd]) if spec[:econo_ctrl_mthd]
        ideal.setHeatRecoveryType(spec[:heat_recovery_type]) if spec[:heat_recovery_type]
        ideal.setSensibleHeatRecoveryEffectiveness(spec[:heat_recovery_sensible_eff]) if spec[:heat_recovery_sensible_eff]
        ideal.setLatentHeatRecoveryEffectiveness(spec[:heat_recovery_latent_eff]) if spec[:heat_recovery_latent_eff]
        # Reference the largest space's design outdoor air object by name, resolved from the model.
        if spec[:design_oa_name]
          dsn_oa = context.model.getDesignSpecificationOutdoorAirByName(spec[:design_oa_name])
          ideal.setDesignSpecificationOutdoorAirObject(dsn_oa.get) if dsn_oa.is_initialized
        end
        ideal
      end

      # @return [OpenStudio::Model::ZoneVentilationDesignFlowRate] the zone ventilation object
      def self.build_zone_ventilation(spec, context)
        ventilation = OpenStudio::Model::ZoneVentilationDesignFlowRate.new(context.model)
        # The flow is given either absolutely or per unit floor area; the ventilation type selects
        # which, and each type carries its own fan and control-temperature envelope.
        design_flow = Quantities.resolve(spec, 'design_flow', :air_flow)
        ventilation.setDesignFlowRate(design_flow) unless design_flow.nil?
        ventilation.setFlowRateperZoneFloorArea(spec[:flow_per_area_m3s]) if spec[:flow_per_area_m3s]
        # ZoneVentilation takes a plain schedule, not an availability schedule, so apply_common's
        # schedule_name handling does not reach it.
        ventilation.setSchedule(context.schedule(spec[:schedule_name])) if spec[:schedule_name]

        pressure = Quantities.resolve(spec, 'fan_pressure_rise', :pressure)
        ventilation.setFanPressureRise(pressure) unless pressure.nil?
        ventilation.setFanTotalEfficiency(spec[:fan_total_eff]) if spec[:fan_total_eff]
        ventilation.setConstantTermCoefficient(spec[:constant_term_coeff]) if spec[:constant_term_coeff]
        ventilation.setVelocityTermCoefficient(spec[:velocity_term_coeff]) if spec[:velocity_term_coeff]
        ventilation.setTemperatureTermCoefficient(spec[:temperature_term_coeff]) if spec[:temperature_term_coeff]

        apply_zone_ventilation_limits(ventilation, spec)
        ventilation.setVentilationType(spec[:ventilation_type]) if spec[:ventilation_type]
        ventilation
      end

      # The indoor / outdoor temperature and wind-speed envelope outside which the ventilation stops.
      #
      # @param ventilation [OpenStudio::Model::ZoneVentilationDesignFlowRate] the ventilation object
      # @param spec [Hash] the spec
      # @return [void]
      def self.apply_zone_ventilation_limits(ventilation, spec)
        min_indoor = Quantities.resolve(spec, 'min_indoor_temp', :temperature)
        ventilation.setMinimumIndoorTemperature(min_indoor) unless min_indoor.nil?
        max_indoor = Quantities.resolve(spec, 'max_indoor_temp', :temperature)
        ventilation.setMaximumIndoorTemperature(max_indoor) unless max_indoor.nil?
        min_outdoor = Quantities.resolve(spec, 'min_outdoor_temp', :temperature)
        ventilation.setMinimumOutdoorTemperature(min_outdoor) unless min_outdoor.nil?
        max_outdoor = Quantities.resolve(spec, 'max_outdoor_temp', :temperature)
        ventilation.setMaximumOutdoorTemperature(max_outdoor) unless max_outdoor.nil?
        delta = Quantities.resolve(spec, 'delta_temp', :temperature_difference)
        ventilation.setDeltaTemperature(delta) unless delta.nil?
        ventilation.setMaximumWindSpeed(spec[:max_wind_speed_m_per_s]) if spec[:max_wind_speed_m_per_s]
        nil
      end

      # @param spec [Hash] a ZoneHVACTerminalUnitVariableRefrigerantFlow spec (requires cu_name). An
      #   +availability_sch_name+ sets the terminal availability, +op_mode_sch_name+ the supply fan
      #   operating mode, +no_ventilation+ zeroes the outdoor air flows, and a +fan+ sub-hash overrides
      #   the built-in supply fan's name, pressure rise, and efficiencies.
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::ZoneHVACTerminalUnitVariableRefrigerantFlow] the terminal
      def self.build_vrf_terminal(spec, context)
        terminal = OpenStudio::Model::ZoneHVACTerminalUnitVariableRefrigerantFlow.new(context.model)
        supply_air = Quantities.resolve(spec, 'sa', :air_flow)
        unless supply_air.nil?
          terminal.setSupplyAirFlowRateDuringCoolingOperation(supply_air)
          terminal.setSupplyAirFlowRateDuringHeatingOperation(supply_air)
        end
        terminal.setTerminalUnitAvailabilityschedule(context.schedule(spec[:availability_sch_name])) if spec[:availability_sch_name]
        terminal.setSupplyAirFanOperatingModeSchedule(context.schedule(spec[:op_mode_sch_name])) if spec[:op_mode_sch_name]
        apply_zone_hvac_no_ventilation(terminal, spec)
        apply_vrf_terminal_fan(terminal, ComponentFactory.symbolize(spec[:fan])) if spec[:fan]
        # attach the terminal to its condensing unit (built earlier, resolved by name)
        context.vrf_cu(spec[:cu_name]).addTerminal(terminal)
        terminal
      end

      # Override the built-in on/off supply fan of a VRF terminal (name, pressure rise, efficiencies).
      #
      # @param terminal [OpenStudio::Model::ZoneHVACTerminalUnitVariableRefrigerantFlow] the terminal
      # @param fan_spec [Hash] the fan override spec
      # @return [void]
      def self.apply_vrf_terminal_fan(terminal, fan_spec)
        fan = terminal.supplyAirFan.to_FanOnOff
        return unless fan.is_initialized

        fan = fan.get
        fan.setName(fan_spec[:name]) if fan_spec[:name]
        pressure = Quantities.resolve(fan_spec, 'pressure_rise', :pressure)
        fan.setPressureRise(pressure) unless pressure.nil?
        fan.setMotorEfficiency(fan_spec[:motor_eff]) if fan_spec[:motor_eff]
        fan.setFanEfficiency(fan_spec[:fan_total_eff]) if fan_spec[:fan_total_eff]
        nil
      end

      # @return [OpenStudio::Model::ZoneHVACHighTemperatureRadiant] the radiant heater
      def self.build_high_temperature_radiant(spec, context)
        radiant = OpenStudio::Model::ZoneHVACHighTemperatureRadiant.new(context.model)
        radiant.setFuelType(spec[:heating_type]) if spec[:heating_type]
        radiant.setCombustionEfficiency(spec[:combustion_efficiency]) if spec[:combustion_efficiency]
        radiant.setFractionofInputConvertedtoRadiantEnergy(spec[:radiant_fraction]) if spec[:radiant_fraction]
        radiant.setHeatingSetpointTemperatureSchedule(context.schedule(spec[:heating_setpoint_sch_name])) if spec[:heating_setpoint_sch_name]
        radiant.setTemperatureControlType(spec[:control_type]) if spec[:control_type]
        radiant.setHeatingThrottlingRange(spec[:throttling_range_k]) if spec[:throttling_range_k]
        radiant
      end

      # ---- composites ----

      # @param spec [Hash] an AirLoopHVACUnitaryHeatCoolVAVChangeoverBypass spec with a +components+ list
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::AirLoopHVACUnitaryHeatCoolVAVChangeoverBypass] the unitary system
      def self.build_unitary_changeover_bypass(spec, context)
        fan = nil
        cooling = nil
        heating = nil
        (spec[:components] || []).each do |raw|
          object = build(symbolize(raw), context)
          case component_kind(object)
          when :fan then fan = object
          when :cooling then cooling = object
          when :heating then heating = object
          end
        end
        unitary = OpenStudio::Model::AirLoopHVACUnitaryHeatCoolVAVChangeoverBypass.new(context.model, fan, cooling, heating)
        unitary.setPriorityControlMode(spec[:priority_ctrl_mode]) if spec[:priority_ctrl_mode]
        fan_operation = spec[:fan_operation] || {}
        unitary.setSupplyAirFanPlacement(fan_operation[:placement]) if fan_operation[:placement]
        unitary
      end

      # @param spec [Hash] a CoilSystemCoolingWaterHXAssist spec (coil_inputs, hx_inputs)
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::CoilSystemCoolingWaterHeatExchangerAssisted] the HX-assisted coil system
      def self.build_coil_system_cooling_water_hx_assist(spec, context)
        system = OpenStudio::Model::CoilSystemCoolingWaterHeatExchangerAssisted.new(context.model)
        if spec[:coil_inputs]
          coil = build(symbolize(spec[:coil_inputs]).merge(obj_type: 'CoilCoolingWater'), context)
          system.setCoolingCoil(coil)
        end
        if spec[:hx_inputs]
          hx = build(symbolize(spec[:hx_inputs]).merge(obj_type: 'HeatExchangerAirToAirSensibleAndLatent'), context)
          system.setHeatExchanger(hx)
        end
        system
      end

      # ---- radiant ----

      # @param spec [Hash] a ZoneHVACLowTemperatureRadiantElectric spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::ZoneHVACLowTemperatureRadiantElectric] the radiant panel
      # @note The radiant surfaces (internal-source constructions) are applied by the system-level
      #   radiant setup, not this component builder.
      def self.build_low_temperature_radiant_electric(spec, context)
        heating_schedule = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(
          context.model, 20.0, name: 'Radiant Electric Heating Control Temp', schedule_type_limit: 'Temperature'
        )
        radiant = OpenStudio::Model::ZoneHVACLowTemperatureRadiantElectric.new(context.model, context.model.alwaysOnDiscreteSchedule, heating_schedule)
        radiant.setRadiantSurfaceType(spec[:surface_type]) if spec[:surface_type]
        radiant.setMaximumElectricalPowertoPanel(spec[:max_elec_w]) if spec[:max_elec_w]
        radiant
      end

      # @param spec [Hash] a ZoneHVACLowTempRadiantVarFlow spec (chilled/hot water loop names)
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::ZoneHVACLowTempRadiantVarFlow] the radiant system
      # @note The radiant surfaces (internal-source constructions) and control strategy are applied
      #   by the system-level radiant setup, not this component builder.
      # @param spec [Hash] a ZoneHVACLowTempRadiantVarFlow spec. The heating and cooling coils are
      #   connected to the named loops; a full spec sets named coil control-temperature schedules, the
      #   control throttling range, hydronic tubing / circuit layout, availability, and temperature /
      #   setpoint control types (matching model_add_low_temp_radiant's per-zone loop). Absent fields
      #   keep the simplified defaults.
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::ZoneHVACLowTempRadiantVarFlow] the radiant loop
      def self.build_low_temp_radiant_var_flow(spec, context)
        heating_schedule = spec[:heating_control_temp_sch_name] ? context.schedule(spec[:heating_control_temp_sch_name]) : OpenstudioStandards::Schedules.create_constant_schedule_ruleset(context.model, 20.0, name: 'Radiant Heating Control Temp', schedule_type_limit: 'Temperature')
        cooling_schedule = spec[:cooling_control_temp_sch_name] ? context.schedule(spec[:cooling_control_temp_sch_name]) : OpenstudioStandards::Schedules.create_constant_schedule_ruleset(context.model, 26.0, name: 'Radiant Cooling Control Temp', schedule_type_limit: 'Temperature')
        throttling = Quantities.resolve(spec, 'throttling_range', :temperature_difference)

        heating_coil = OpenStudio::Model::CoilHeatingLowTempRadiantVarFlow.new(context.model, heating_schedule)
        heating_coil.setName(spec[:heating_coil_name]) if spec[:heating_coil_name]
        heating_coil.setHeatingControlThrottlingRange(throttling) unless throttling.nil?
        context.plant_loop(spec[:hot_water_loop_name]).addDemandBranchForComponent(heating_coil) if spec[:hot_water_loop_name]

        cooling_coil = OpenStudio::Model::CoilCoolingLowTempRadiantVarFlow.new(context.model, cooling_schedule)
        cooling_coil.setName(spec[:cooling_coil_name]) if spec[:cooling_coil_name]
        cooling_coil.setCoolingControlThrottlingRange(throttling) unless throttling.nil?
        context.plant_loop(spec[:chilled_water_loop_name]).addDemandBranchForComponent(cooling_coil) if spec[:chilled_water_loop_name]

        availability = spec[:schedule_name] ? context.schedule(spec[:schedule_name]) : context.model.alwaysOnDiscreteSchedule
        radiant = OpenStudio::Model::ZoneHVACLowTempRadiantVarFlow.new(context.model, availability, heating_coil, cooling_coil)
        radiant.setRadiantSurfaceType(spec[:radiant_type] == 'ceiling' ? 'Ceilings' : 'Floors') if spec[:radiant_type]
        radiant.setHydronicTubingInsideDiameter(spec[:tubing_inside_diameter_m]) if spec[:tubing_inside_diameter_m]
        radiant.setNumberofCircuits(spec[:number_of_circuits]) if spec[:number_of_circuits]
        radiant.setCircuitLength(spec[:circuit_length_m]) if spec[:circuit_length_m]
        radiant.setTemperatureControlType(spec[:temperature_control_type]) if spec[:temperature_control_type]
        radiant.setSetpointControlType(spec[:setpoint_control_type]) if spec[:setpoint_control_type]
        radiant
      end

      # ---- final builders ----

      # @param spec [Hash] an AirSourceHeatPump spec (plant_loop_name, cop)
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::PlantComponentUserDefined] the heat pump proxy (self-placed on the loop)
      # @note This is a self-placing plant component: the EMS-based creator adds it to its loop and
      #   sets up its heating program. The plant builder skips re-placing components already on a loop.
      def self.build_air_source_heat_pump(spec, context)
        loop = context.plant_loop(spec[:plant_loop_name])
        OpenstudioStandards::HVAC.create_central_air_source_heat_pump(context.model, loop, cop: spec[:cop] || 3.65)
      end

      # @param spec [Hash] a ZoneHVACUnitVentilator spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::ZoneHVACUnitVentilator] the unit ventilator
      def self.build_unit_ventilator(spec, context)
        fan = spec[:components] ? classify_zone_hvac_components(spec[:components], context)[0] : build({ obj_type: 'FanConstantVolume' }, context)
        unit_ventilator = OpenStudio::Model::ZoneHVACUnitVentilator.new(context.model, fan)
        max_flow = Quantities.resolve(spec, 'max_supply_airflow', :air_flow)
        unit_ventilator.setMaximumSupplyAirFlowRate(max_flow) unless max_flow.nil?
        unit_ventilator
      end

      # @param spec [Hash] a ZoneHVACEnergyRecoveryVentilator spec. With explicit +hx+, +supply_fan+,
      #   and +exhaust_fan+ sub-hashes the components are built from them and a controller is attached;
      #   otherwise a default ERV is created.
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::ZoneHVACEnergyRecoveryVentilator] the ERV
      def self.build_energy_recovery_ventilator(spec, context)
        return OpenStudio::Model::ZoneHVACEnergyRecoveryVentilator.new(context.model) unless spec[:hx]

        hx = build(symbolize(spec[:hx]).merge(obj_type: 'HeatExchangerAirToAirSensibleAndLatent'), context)
        supply_fan = build(symbolize(spec[:supply_fan]), context)
        exhaust_fan = build(symbolize(spec[:exhaust_fan]), context)
        erv = OpenStudio::Model::ZoneHVACEnergyRecoveryVentilator.new(context.model, hx, supply_fan, exhaust_fan)

        controller = OpenStudio::Model::ZoneHVACEnergyRecoveryVentilatorController.new(context.model)
        controller.setName(spec[:controller_name]) if spec[:controller_name]
        controller.setControlHighIndoorHumidityBasedonOutdoorHumidityRatio(spec[:high_humidity_control]) unless spec[:high_humidity_control].nil?
        erv.setController(controller)

        supply_flow = Quantities.resolve(spec, 'supply_flow', :air_flow)
        erv.setSupplyAirFlowRate(supply_flow) unless supply_flow.nil?
        exhaust_flow = Quantities.resolve(spec, 'exhaust_flow', :air_flow)
        erv.setExhaustAirFlowRate(exhaust_flow) unless exhaust_flow.nil?
        erv.setVentilationRateperUnitFloorArea(spec[:vent_per_area_m3s_m2]) if spec[:vent_per_area_m3s_m2]
        erv.setVentilationRateperOccupant(spec[:vent_per_occupant_m3s]) unless spec[:vent_per_occupant_m3s].nil?
        erv
      end

      # @param spec [Hash] a ZoneHVACWindowAirConditioner spec (eer, shr)
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::ZoneHVACPackagedTerminalAirConditioner] a packaged terminal unit configured as a window AC
      # @note OpenStudio has no dedicated window air conditioner class; a window AC is modeled as a
      #   packaged terminal air conditioner with DX cooling and minimal electric heat.
      def self.build_window_ac(spec, context)
        fan = build({ obj_type: 'FanOnOff' }, context)
        cooling = build({ obj_type: 'CoilCoolingDXSingleSpeed' }, context)
        dx = cooling.to_CoilCoolingDXSingleSpeed.get
        dx.setRatedCOP(OpenstudioStandards::HVAC.eer_to_cop(spec[:eer])) if spec[:eer]
        dx.setRatedSensibleHeatRatio(spec[:shr]) if spec[:shr]
        heating = build({ obj_type: 'CoilHeatingElectric' }, context)
        OpenStudio::Model::ZoneHVACPackagedTerminalAirConditioner.new(context.model, context.model.alwaysOnDiscreteSchedule, fan, heating, cooling)
      end

      # @param spec [Hash] a CoilCoolingWater spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::CoilCoolingWater] the coil (water side connected by apply_common)
      def self.build_coil_cooling_water(spec, context)
        coil = OpenStudio::Model::CoilCoolingWater.new(context.model)
        coil.setHeatExchangerConfiguration('CrossFlow')
        ewt = Quantities.resolve(spec, 'ewt', :temperature)
        if ewt.nil?
          coil.autosizeDesignInletWaterTemperature
        else
          coil.setDesignInletWaterTemperature(ewt)
        end
        eat = Quantities.resolve(spec, 'eat', :temperature)
        coil.setDesignInletAirTemperature(eat) unless eat.nil?
        lat = Quantities.resolve(spec, 'lat', :temperature)
        coil.setDesignOutletAirTemperature(lat) unless lat.nil?
        water_flow = Quantities.resolve(spec, 'water_flow', :water_flow)
        coil.setDesignWaterFlowRate(water_flow) unless water_flow.nil?
        air_flow = Quantities.resolve(spec, 'air_flow', :air_flow)
        coil.setDesignAirFlowRate(air_flow) unless air_flow.nil?
        coil.setDesignInletAirHumidityRatio(spec[:eahr_kgpkg]) if spec[:eahr_kgpkg]
        coil.setDesignOutletAirHumidityRatio(spec[:lahr_kgpkg]) if spec[:lahr_kgpkg]
        coil
      end

      # @param spec [Hash] a CoilHeatingWater spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::CoilHeatingWater] the coil (water side connected by apply_common)
      def self.build_coil_heating_water(spec, context)
        coil = OpenStudio::Model::CoilHeatingWater.new(context.model)
        ewt, lwt = heating_coil_water_temperatures(spec, context)
        coil.setRatedInletWaterTemperature(ewt) unless ewt.nil?
        coil.setRatedOutletWaterTemperature(lwt) unless lwt.nil?
        eat = Quantities.resolve(spec, 'eat', :temperature)
        coil.setRatedInletAirTemperature(eat) unless eat.nil?
        lat = Quantities.resolve(spec, 'lat', :temperature)
        coil.setRatedOutletAirTemperature(lat) unless lat.nil?
        water_flow = Quantities.resolve(spec, 'water_flow', :water_flow)
        coil.setMaximumWaterFlowRate(water_flow) unless water_flow.nil?
        capacity = Quantities.resolve(spec, 'capacity', :capacity)
        coil.setRatedCapacity(capacity) unless capacity.nil?
        ua = spec[:ua_si] || (spec[:ua_ip] && OpenStudio.convert(spec[:ua_ip], 'Btu/hr*R', 'W/K').get)
        coil.setUFactorTimesAreaValue(ua) if ua
        coil
      end

      # The rated entering and leaving water temperatures of a hot-water coil: as given, else the
      # serving loop's design exit temperature and that less the loop design temperature difference.
      #
      # @param spec [Hash] a CoilHeatingWater spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [Array(Float, Float)] entering and leaving water temperatures (C), either nil when
      #   neither the spec nor a loop supplies it
      def self.heating_coil_water_temperatures(spec, context)
        ewt = Quantities.resolve(spec, 'ewt', :temperature)
        lwt = Quantities.resolve(spec, 'lwt', :temperature)
        return [ewt, lwt] if ewt && lwt

        loop = spec[:plant_loop_name] && context.plant_loop(spec[:plant_loop_name])
        return [ewt, lwt] unless loop

        sizing = loop.sizingPlant
        ewt ||= sizing.designLoopExitTemperature
        lwt ||= ewt - sizing.loopDesignTemperatureDifference
        [ewt, lwt]
      end

      # @param spec [Hash] a ChillerElectricEIR spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::ChillerElectricEIR] the chiller (condenser side connected by apply_common)
      def self.build_chiller_electric_eir(spec, context)
        # The single-argument constructor supplies default performance curves.
        chiller = OpenStudio::Model::ChillerElectricEIR.new(context.model)
        chiller.setReferenceCOP(spec[:cop]) if spec[:cop]
        capacity = Quantities.resolve(spec, 'capacity', :capacity)
        chiller.setReferenceCapacity(capacity) unless capacity.nil?
        leaving_chw = Quantities.resolve(spec, 'leaving_chw_temp', :temperature)
        chiller.setReferenceLeavingChilledWaterTemperature(leaving_chw) unless leaving_chw.nil?
        entering_cw = Quantities.resolve(spec, 'entering_cw_temp', :temperature)
        chiller.setReferenceEnteringCondenserFluidTemperature(entering_cw) unless entering_cw.nil?
        chw_flow = Quantities.resolve(spec, 'chw_flow', :water_flow)
        chiller.setReferenceChilledWaterFlowRate(chw_flow) unless chw_flow.nil?
        cw_flow = Quantities.resolve(spec, 'cw_flow', :water_flow)
        chiller.setReferenceCondenserFluidFlowRate(cw_flow) unless cw_flow.nil?
        lower_limit = Quantities.resolve(spec, 'leaving_chw_lower_limit', :temperature)
        chiller.setLeavingChilledWaterLowerTemperatureLimit(lower_limit) unless lower_limit.nil?
        chiller.setMinimumPartLoadRatio(spec[:min_plr]) if spec[:min_plr]
        chiller.setMaximumPartLoadRatio(spec[:max_plr]) if spec[:max_plr]
        chiller.setOptimumPartLoadRatio(spec[:opt_plr]) if spec[:opt_plr]
        chiller.setMinimumUnloadingRatio(spec[:min_unloading_ratio]) if spec[:min_unloading_ratio]
        chiller.setChillerFlowMode(spec[:flow_mode]) if spec[:flow_mode]
        chiller.setSizingFactor(spec[:sizing_factor]) if spec[:sizing_factor]
        condenser_type = spec[:condenser_type] || (spec[:condenser_loop_name] ? 'WaterCooled' : 'AirCooled')
        chiller.setCondenserType(condenser_type)
        chiller
      end

      # @param spec [Hash] a CoolingTowerVariableSpeed spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::CoolingTowerVariableSpeed] the cooling tower
      def self.build_cooling_tower_variable_speed(spec, context)
        tower = OpenStudio::Model::CoolingTowerVariableSpeed.new(context.model)
        water_flow = Quantities.resolve(spec, 'water_flow', :water_flow)
        tower.setDesignWaterFlowRate(water_flow) unless water_flow.nil?
        air_flow = Quantities.resolve(spec, 'air_flow', :air_flow)
        tower.setDesignAirFlowRate(air_flow) unless air_flow.nil?
        tower.setDesignFanPower(spec[:fan_power_w]) if spec[:fan_power_w]
        # Only the variable-speed tower exposes its design temperatures and part-load fan power.
        range = Quantities.resolve(spec, 'design_range_temp', :temperature_difference)
        tower.setDesignRangeTemperature(range) unless range.nil?
        approach = Quantities.resolve(spec, 'design_approach_temp', :temperature_difference)
        tower.setDesignApproachTemperature(approach) unless approach.nil?
        tower.setFractionofTowerCapacityinFreeConvectionRegime(spec[:free_convection_capacity_frac]) if spec[:free_convection_capacity_frac]
        tower.setFanPowerRatioFunctionofAirFlowRateRatioCurve(context.curve(spec[:fan_power_ratio_curve])) if spec[:fan_power_ratio_curve]
        tower.setSizingFactor(spec[:sizing_factor]) if spec[:sizing_factor]
        tower.setNumberofCells(spec[:num_cells]) if spec[:num_cells]
        tower
      end

      # @param spec [Hash] a DistrictCooling / DistrictHeatingWater / DistrictHeatingSteam spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::ModelObject] the district plant object
      def self.build_district(spec, context)
        klass = case spec[:obj_type]
                when 'DistrictCooling' then OpenStudio::Model::DistrictCooling
                when 'DistrictHeatingWater' then OpenStudio::Model::DistrictHeatingWater
                when 'DistrictHeatingSteam' then OpenStudio::Model::DistrictHeatingSteam
                end
        object = klass.new(context.model)
        capacity = Quantities.resolve(spec, 'capacity', :capacity)
        if capacity.nil? || spec[:autosize]
          object.autosizeNominalCapacity
        else
          object.setNominalCapacity(capacity)
        end
        object
      end

      # Apply the fields shared by the single pump types from the spec.
      #
      # @param pump [OpenStudio::Model::ModelObject] a PumpVariableSpeed or PumpConstantSpeed
      # @param spec [Hash] the component spec
      # @return [OpenStudio::Model::ModelObject] the pump
      def self.apply_pump_common(pump, spec)
        head = Quantities.resolve(spec, 'pump_head', :pump_head)
        pump.setRatedPumpHead(head) unless head.nil?
        flow = Quantities.resolve(spec, 'pump_flow', :water_flow)
        pump.setRatedFlowRate(flow) unless flow.nil?
        pump.setRatedPowerConsumption(spec[:pump_power_w]) if spec[:pump_power_w]
        pump.setMotorEfficiency(spec[:motor_efficiency]) if spec[:motor_efficiency]
        pump.setPumpControlType(spec[:pump_ctrl_type]) if spec[:pump_ctrl_type]
        pump
      end

      # Set a variable speed pump's part-load performance curve from explicit user coefficients.
      #
      # @param pump [OpenStudio::Model::PumpVariableSpeed] the pump
      # @param coeffs [Array<Numeric>] the four part-load curve coefficients
      # @return [void]
      def self.set_pump_plr_coefficients(pump, coeffs)
        pump.setCoefficient1ofthePartLoadPerformanceCurve(coeffs[0])
        pump.setCoefficient2ofthePartLoadPerformanceCurve(coeffs[1])
        pump.setCoefficient3ofthePartLoadPerformanceCurve(coeffs[2])
        pump.setCoefficient4ofthePartLoadPerformanceCurve(coeffs[3])
        nil
      end

      # Apply the fields shared by the simple fan types directly from the spec.
      #
      # @param fan [OpenStudio::Model::ModelObject] a FanOnOff, FanConstantVolume, or FanVariableVolume
      # @param spec [Hash] the component spec
      # @return [OpenStudio::Model::ModelObject] the fan
      def self.apply_fan_fields(fan, spec)
        fan.setFanEfficiency(spec[:fan_total_eff]) if spec[:fan_total_eff]
        fan.setMotorEfficiency(spec[:motor_eff]) if spec[:motor_eff]
        fan.setMotorInAirstreamFraction(spec[:motor_airstream_frac]) if spec[:motor_airstream_frac]
        fan.setEndUseSubcategory(spec[:enduse_subcat]) if spec[:enduse_subcat]
        pressure = Quantities.resolve(spec, 'pressure_rise', :pressure)
        fan.setPressureRise(pressure) unless pressure.nil?
        max_flow = Quantities.resolve(spec, 'max_airflow', :air_flow)
        fan.setMaximumFlowRate(max_flow) unless max_flow.nil?
        fan
      end
    end
  end
end
