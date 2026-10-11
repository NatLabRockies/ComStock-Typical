module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Creator:EmsBuilder
    # Builds EnergyManagementSystem objects from a declarative +ems_info+ entry.
    #
    # Objects are created in the order EnergyPlus resolves references — sensors, internal variables,
    # global variables, actuators, programs, calling managers, then output variables — so a program
    # body may reference any earlier object by its runtime-language name. Sensors and actuators
    # deduplicate by name so repeated entries reuse the existing object. EMS runs last in the
    # orchestrator, after every HVAC object exists, so actuators and sensors can target any of them.
    module EmsBuilder
      # Build every EnergyManagementSystem object in an ems_info entry.
      #
      # @param spec [Hash] an emsEntry spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [void]
      def self.build(spec, context)
        spec = ComponentFactory.deep_symbolize(spec)
        (spec[:sensors] || []).each { |sensor| build_sensor(sensor, context) }
        (spec[:internal_vars] || []).each { |internal_var| build_internal_variable(internal_var, context) }
        (spec[:global_vars] || []).each { |name| OpenStudio::Model::EnergyManagementSystemGlobalVariable.new(context.model, name) }
        (spec[:actuators] || []).each { |actuator| build_actuator(actuator, context) }
        (spec[:programs] || []).each { |program| build_program(program, context) }
        (spec[:calling_managers] || []).each { |manager| build_calling_manager(manager, context) }
        (spec[:output_variables] || []).each { |output_variable| build_output_variable(output_variable, context) }
        nil
      end

      # Build a sensor, reusing an existing sensor of the same name.
      #
      # @param spec [Hash] a sensor spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::EnergyManagementSystemSensor] the sensor
      def self.build_sensor(spec, context)
        existing = context.model.getEnergyManagementSystemSensorByName(spec[:name])
        return existing.get if existing.is_initialized

        sensor = OpenStudio::Model::EnergyManagementSystemSensor.new(context.model, spec[:variable])
        sensor.setName(spec[:name])
        sensor.setKeyName(spec[:keyname])
        sensor
      end

      # Build an internal variable.
      #
      # @param spec [Hash] an internal_vars spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::EnergyManagementSystemInternalVariable] the internal variable
      def self.build_internal_variable(spec, context)
        internal_var = OpenStudio::Model::EnergyManagementSystemInternalVariable.new(context.model, spec[:data_type])
        internal_var.setName(spec[:name])
        internal_var.setInternalDataIndexKeyName(spec[:key_name]) if spec[:key_name]
        internal_var
      end

      # Build an actuator, reusing an existing actuator of the same name. The actuated object is a
      # named model object, or a constant schedule created (or reused) from +create_schedule_constant+.
      #
      # @param spec [Hash] an actuators spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::EnergyManagementSystemActuator] the actuator
      def self.build_actuator(spec, context)
        existing = context.model.getEnergyManagementSystemActuatorByName(spec[:name])
        return existing.get if existing.is_initialized

        component = actuated_component(spec, context)
        actuator = OpenStudio::Model::EnergyManagementSystemActuator.new(component, spec[:component_type], spec[:control_type])
        actuator.setName(spec[:name])
        actuator
      end

      # Resolve the object an actuator drives: a constant schedule created from
      # +create_schedule_constant+, or an existing model object matched by name.
      #
      # @param spec [Hash] an actuators spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::ModelObject] the actuated object
      # @raise [ArgumentError] when the named component is not present in the model
      def self.actuated_component(spec, context)
        return constant_schedule(spec, context) if spec.key?(:create_schedule_constant)

        found = context.model.getModelObjectByName(spec[:component_name])
        raise ArgumentError, "EMS actuator '#{spec[:name]}' references unknown component '#{spec[:component_name]}'" unless found.is_initialized

        found.get
      end

      # Create or reuse a constant schedule named after the actuator's component, used as the
      # actuated object.
      #
      # @param spec [Hash] an actuators spec with +create_schedule_constant+
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::ScheduleConstant] the schedule
      def self.constant_schedule(spec, context)
        OpenstudioStandards::Schedules.create_schedule_constant(context.model, spec[:create_schedule_constant],
                                                                name: spec[:component_name],
                                                                schedule_type_limit: spec[:schedule_type_limit])
      end

      # Build a program from its newline-separated runtime-language body.
      #
      # @param spec [Hash] a programs spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::EnergyManagementSystemProgram] the program
      def self.build_program(spec, context)
        program = OpenStudio::Model::EnergyManagementSystemProgram.new(context.model)
        program.setName(spec[:name])
        program.setBody(spec[:body])
        program
      end

      # Build a program calling manager and attach its named programs.
      #
      # @param spec [Hash] a calling_managers spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::EnergyManagementSystemProgramCallingManager] the calling manager
      # @raise [ArgumentError] when a referenced program is not defined
      def self.build_calling_manager(spec, context)
        manager = OpenStudio::Model::EnergyManagementSystemProgramCallingManager.new(context.model)
        manager.setName(spec[:name])
        manager.setCallingPoint(spec[:calling_point])
        (spec[:program_names] || []).each do |program_name|
          program = context.model.getEnergyManagementSystemProgramByName(program_name)
          raise ArgumentError, "EMS calling manager '#{spec[:name]}' references unknown program '#{program_name}'" unless program.is_initialized

          manager.addProgram(program.get)
        end
        manager
      end

      # Build an output variable reporting an EMS variable.
      #
      # @param spec [Hash] an output_variables spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::EnergyManagementSystemOutputVariable] the output variable
      def self.build_output_variable(spec, context)
        output_variable = OpenStudio::Model::EnergyManagementSystemOutputVariable.new(context.model, spec[:ems_var_name])
        output_variable.setName(spec[:name])
        output_variable.setTypeOfDataInVariable(spec[:data_type]) if spec[:data_type]
        output_variable.setUpdateFrequency(spec[:update_freq]) if spec[:update_freq]
        output_variable.setUnits(spec[:units]) if spec[:units]
        if spec[:prog_name]
          program = context.model.getEnergyManagementSystemProgramByName(spec[:prog_name])
          output_variable.setEMSProgramOrSubroutineName(program.get) if program.is_initialized
        end
        output_variable
      end
    end
  end
end
