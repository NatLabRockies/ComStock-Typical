module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Creator:ApplyHvac
    # Orchestrates the HVAC creator: builds every system in a spec in dependency order.

    # Apply an HVAC creator spec to a model, building plant loops, air systems, and zone HVAC in
    # the order that lets name references resolve (plant loops, then air systems, then zones).
    #
    # @param model [OpenStudio::Model::Model] the model to build into (zones must already exist)
    # @param spec [Hash] a spec conforming to the HVAC creator schema
    # @return [OpenstudioStandards::HVAC::BuildContext] the build context, exposing the created
    #   loops and the collected log messages
    def self.apply_hvac(model, spec)
      spec = ComponentFactory.deep_symbolize(spec)
      context = BuildContext.new(model)

      # Structural check first, so a malformed spec fails naming the offending path instead of
      # deep inside a builder with an OpenStudio-level message.
      Validation.check(spec).each { |warning| context.warn(warning) }

      # Schedules first: any section may name one, including the loop-level setpoint managers that
      # are placed before their loop's equipment exists.
      (spec[:schedules] || []).each { |schedule_spec| build_schedule(schedule_spec, context) }

      (spec[:plant_loop_info] || []).each { |loop_spec| PlantLoopBuilder.build(loop_spec, context) }
      (spec[:vrf_info] || []).each { |vrf_spec| VrfBuilder.build(vrf_spec, context) }
      (spec[:air_system_info] || []).each { |air_spec| AirLoopBuilder.build(air_spec, context) }
      (spec[:doas_info] || []).each { |doas_spec| DoasBuilder.build(doas_spec, context) }
      (spec[:zone_info] || []).each { |zone_spec| ZoneBuilder.build(zone_spec, context) }

      # Deferred cross-loop passes declared on plant loops, applied after all loops and zones exist.
      PostSteps.apply(spec, context)
      # EMS last, so programs may reference any HVAC object built above by name.
      (spec[:ems_info] || []).each { |ems_spec| EmsBuilder.build(ems_spec, context) }

      write_building_properties(model, spec)
      context
    end

    # Create one constant schedule a spec declares.
    #
    # A Schedule:Constant is a distinct class from a schedule ruleset, and only it can be the target
    # of an EnergyManagementSystem actuator, so +constant_object+ selects which is built.
    #
    # @param spec [Hash] a schedules entry
    # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
    # @return [OpenStudio::Model::Schedule] the schedule
    def self.build_schedule(spec, context)
      value = Quantities.resolve(spec, 'value', :temperature) || spec[:value]
      raise ArgumentError, "schedule '#{spec[:name]}' needs a value" if value.nil?

      if spec[:constant_object]
        OpenstudioStandards::Schedules.create_schedule_constant(context.model, value,
                                                                name: spec[:name],
                                                                schedule_type_limit: spec[:type_limits])
      else
        OpenstudioStandards::Schedules.create_constant_schedule_ruleset(context.model, value,
                                                                        name: spec[:name],
                                                                        schedule_type_limit: spec[:type_limits])
      end
    end

    # Record the spec identity on the Building additional properties.
    #
    # @param model [OpenStudio::Model::Model] the model
    # @param spec [Hash] the spec
    # @return [void]
    def self.write_building_properties(model, spec)
      # Only touch the Building when there is something to record, so applying a spec that carries no
      # identity metadata does not materialize a Building object that was not otherwise present.
      return if spec[:custom_system_type].nil? && spec[:description].nil? && spec[:schema_version].nil?

      properties = model.getBuilding.additionalProperties
      properties.setFeature('custom_system_type', spec[:custom_system_type]) if spec[:custom_system_type]
      properties.setFeature('custom_system_description', spec[:description]) if spec[:description]
      properties.setFeature('hvac_schema_version', spec[:schema_version]) if spec[:schema_version]
      nil
    end
  end
end
