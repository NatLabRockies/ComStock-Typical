module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Creator:BuildContext
    # Shared state threaded through the HVAC creator builders.
    #
    # A BuildContext wraps the model under construction and provides:
    # - name-based lookup of loops, zones, and variable refrigerant flow condensing units,
    #   preferring objects created during this run before falling back to objects already in
    #   the model (which supports retrofit specs);
    # - schedule resolution that honors the AlwaysOn and AlwaysOff sentinels and creates a
    #   constant schedule only when an explicit fallback value is supplied;
    # - performance-curve resolution from a name or a [source, key] pair;
    # - collection of warning and error messages, also emitted to the OpenStudio log.
    class BuildContext
      # OpenStudio log channel used by the creator.
      LOG_CHANNEL = 'openstudio.HVAC.Creator'.freeze

      # @return [OpenStudio::Model::Model] the model under construction
      attr_reader :model

      # @return [Array<Hash>] collected log messages, each { level:, message: }
      attr_reader :messages

      # @param model [OpenStudio::Model::Model] the model under construction
      def initialize(model)
        @model = model
        @plant_loops = {}
        @air_loops = {}
        @vrf_units = {}
        @messages = []
      end

      # Plant loops created during this run, keyed by name.
      #
      # @return [Hash{String => OpenStudio::Model::PlantLoop}] the created plant loops
      def plant_loops
        @plant_loops.dup
      end

      # Air loops created during this run, keyed by name.
      #
      # @return [Hash{String => OpenStudio::Model::AirLoopHVAC}] the created air loops
      def air_loops
        @air_loops.dup
      end

      # Variable refrigerant flow condensing units created during this run, keyed by name.
      #
      # @return [Hash{String => OpenStudio::Model::AirConditionerVariableRefrigerantFlow}] the units
      def vrf_units
        @vrf_units.dup
      end

      # Register a plant loop created during this run so later references resolve to it.
      #
      # @param name [String] the reference name
      # @param loop [OpenStudio::Model::PlantLoop] the loop
      # @return [OpenStudio::Model::PlantLoop] the loop
      def register_plant_loop(name, loop)
        @plant_loops[name.to_s] = loop
      end

      # Register an air loop created during this run.
      #
      # @param name [String] the reference name
      # @param loop [OpenStudio::Model::AirLoopHVAC] the loop
      # @return [OpenStudio::Model::AirLoopHVAC] the loop
      def register_air_loop(name, loop)
        @air_loops[name.to_s] = loop
      end

      # Register a variable refrigerant flow condensing unit created during this run.
      #
      # @param name [String] the reference name
      # @param unit [OpenStudio::Model::AirConditionerVariableRefrigerantFlow] the condensing unit
      # @return [OpenStudio::Model::AirConditionerVariableRefrigerantFlow] the condensing unit
      def register_vrf_cu(name, unit)
        @vrf_units[name.to_s] = unit
      end

      # Resolve a plant loop by name.
      #
      # @param name [String] the reference name
      # @return [OpenStudio::Model::PlantLoop] the loop
      # @raise [ArgumentError] when no loop of that name is defined this run or present in the model
      def plant_loop(name)
        resolve_reference(name, @plant_loops, 'plant loop') { |n| @model.getPlantLoopByName(n) }
      end

      # Resolve an air loop by name.
      #
      # @param name [String] the reference name
      # @return [OpenStudio::Model::AirLoopHVAC] the loop
      # @raise [ArgumentError] when no loop of that name is defined this run or present in the model
      def air_loop(name)
        resolve_reference(name, @air_loops, 'air loop') { |n| @model.getAirLoopHVACByName(n) }
      end

      # Resolve a variable refrigerant flow condensing unit by name.
      #
      # @param name [String] the reference name
      # @return [OpenStudio::Model::AirConditionerVariableRefrigerantFlow] the condensing unit
      # @raise [ArgumentError] when no unit of that name is defined this run or present in the model
      def vrf_cu(name)
        resolve_reference(name, @vrf_units, 'variable refrigerant flow condensing unit') do |n|
          @model.getAirConditionerVariableRefrigerantFlowByName(n)
        end
      end

      # Resolve a thermal zone by name. Zones pre-exist in the model geometry.
      #
      # @param name [String] the zone name
      # @return [OpenStudio::Model::ThermalZone] the zone
      # @raise [ArgumentError] when the zone is not present in the model
      def zone(name)
        result = @model.getThermalZoneByName(name.to_s)
        raise ArgumentError, "thermal zone '#{name}' is not present in the model" unless result.is_initialized

        result.get
      end

      # Resolve a schedule by name, creating a constant schedule only when a fallback is given.
      #
      # The AlwaysOn and AlwaysOff sentinels resolve to the model's always-on and always-off
      # discrete schedules. Any other name must reference an existing schedule; when it does not
      # and +constant_value+ is supplied, a constant schedule of that value is created, otherwise
      # an error is raised (a missing named schedule is treated as an authoring error, not an
      # implicit request to create one).
      #
      # @param name [String] the schedule name or sentinel
      # @param constant_value [Numeric, nil] value for a created constant schedule when the name is absent
      # @param type_limits [String, nil] schedule type limits name for a created constant schedule
      # @return [OpenStudio::Model::Schedule] the schedule
      # @raise [ArgumentError] when the named schedule is absent and no constant_value fallback is given
      def schedule(name, constant_value: nil, type_limits: nil)
        return @model.alwaysOnDiscreteSchedule if name.to_s == 'AlwaysOn'
        return @model.alwaysOffDiscreteSchedule if name.to_s == 'AlwaysOff'

        existing = @model.getScheduleByName(name.to_s)
        return existing.get if existing.is_initialized

        unless constant_value.nil?
          return OpenstudioStandards::Schedules.create_constant_schedule_ruleset(@model, constant_value,
                                                                                 name: name.to_s,
                                                                                 schedule_type_limit: type_limits)
        end

        raise ArgumentError, "schedule '#{name}' is not present in the model"
      end

      # Resolve a performance curve from any curve reference: a user-entered curve object, a
      # [source, key] pair, or a bare name. Delegates to the typed-coefficient resolver.
      #
      # @param reference [Hash, Array<String>, String] a curve reference
      # @return [OpenStudio::Model::Curve] the curve
      # @raise [ArgumentError] when the curve cannot be resolved
      def curve(reference)
        Coefficients.resolve_curve(self, reference)
      end

      # Resolve a named curve (a [source, key] pair or a bare name) by looking it up in the model.
      # The packaged curve library is a future data-backed source.
      #
      # @param reference [Array<String>, String] a [source, key] pair or a bare curve name
      # @return [OpenStudio::Model::Curve] the curve
      # @raise [ArgumentError] when the curve cannot be resolved
      def curve_by_name(reference)
        if reference.is_a?(Array)
          source, key = reference
          raise ArgumentError, "curve reference #{reference.inspect} must be a [source, key] pair" if key.nil?

          resolved = @model.getCurveByName(key.to_s)
          return resolved.get if resolved.is_initialized

          raise ArgumentError, "curve '#{key}' from source '#{source}' is not available in the model"
        end

        resolved = @model.getCurveByName(reference.to_s)
        raise ArgumentError, "curve '#{reference}' is not present in the model" unless resolved.is_initialized

        resolved.get
      end

      # Record a warning, emitting it to the OpenStudio log.
      #
      # @param message [String] the warning message
      # @return [void]
      def warn(message)
        log(OpenStudio::Warn, message)
      end

      # Record an error, emitting it to the OpenStudio log.
      #
      # @param message [String] the error message
      # @return [void]
      def error(message)
        log(OpenStudio::Error, message)
      end

      private

      # @param name [String] the reference name
      # @param registry [Hash] objects created this run, keyed by name
      # @param label [String] a human-readable object kind for the error message
      # @yield [String] a block resolving the name in the model, returning a boost optional
      # @return [Object] the resolved object
      def resolve_reference(name, registry, label)
        key = name.to_s
        return registry[key] if registry.key?(key)

        found = yield(key)
        return found.get if found.is_initialized

        raise ArgumentError, "#{label} '#{name}' is not defined earlier in the spec or present in the model"
      end

      # @param level [OpenStudio::LogLevel] the log level
      # @param message [String] the message
      # @return [void]
      def log(level, message)
        @messages << { level: level, message: message }
        OpenStudio.logFree(level, LOG_CHANNEL, message)
        nil
      end
    end
  end
end
