module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Creator:DoasBuilder
    # Builds a dedicated outdoor air system (AirLoopHVACDedicatedOutdoorAirSystem) from a creator
    # spec.
    #
    # System layer: it builds an outdoor air system and its conditioning components via the
    # component factory (disconnected), wraps them in a dedicated outdoor air system, attaches the
    # served air loops (resolved by name), and places the outdoor-air-stream and relief components
    # and the supply setpoint managers. See the two-layer architecture in the implementation plan.
    module DoasBuilder
      # Build a dedicated outdoor air system and connect it to its served air loops.
      #
      # @param spec [Hash] a doas spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::AirLoopHVACDedicatedOutdoorAirSystem] the dedicated OA system
      def self.build(spec, context)
        spec = ComponentFactory.deep_symbolize(spec)
        controller = OpenStudio::Model::ControllerOutdoorAir.new(context.model)
        oa_system = OpenStudio::Model::AirLoopHVACOutdoorAirSystem.new(context.model, controller)
        doas = OpenStudio::Model::AirLoopHVACDedicatedOutdoorAirSystem.new(oa_system)
        doas.setName(spec[:name]) if spec[:name]

        apply_design_conditions(doas, spec)
        (spec[:air_loops] || []).each { |name| doas.addAirLoop(served_air_loop(name, spec, context)) }
        inboard = place_components(oa_system, spec[:components] || [], context)
        place_relief_components(oa_system, spec[:relief_components] || [], context)
        place_controls(inboard, spec[:controls] || [], context)
        apply_availability(doas, spec[:availability], context) if spec[:availability]

        doas
      end

      # Resolve a served air loop by name, requiring it to have an outdoor air system (the dedicated
      # outdoor air system connects to each served loop's outdoor air mixer).
      #
      # @param name [String] the served air loop name
      # @param spec [Hash] the doas spec, for messaging
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::AirLoopHVAC] the served air loop
      # @raise [ArgumentError] when the served loop has no outdoor air system
      def self.served_air_loop(name, spec, context)
        air_loop = context.air_loop(name)
        unless air_loop.airLoopHVACOutdoorAirSystem.is_initialized
          raise ArgumentError, "air loop '#{name}' served by dedicated outdoor air system '#{spec[:name]}' must have an outdoor air system"
        end

        air_loop
      end

      # Apply the preheat and precool design conditions (temperatures and humidity ratios).
      #
      # @param doas [OpenStudio::Model::AirLoopHVACDedicatedOutdoorAirSystem] the dedicated OA system
      # @param spec [Hash] the doas spec
      # @return [void]
      def self.apply_design_conditions(doas, spec)
        precool_t = Quantities.resolve(spec, 'precool_des_t', :temperature)
        doas.setPrecoolDesignTemperature(precool_t) unless precool_t.nil?
        preheat_t = Quantities.resolve(spec, 'preheat_des_t', :temperature)
        doas.setPreheatDesignTemperature(preheat_t) unless preheat_t.nil?
        doas.setPrecoolDesignHumidityRatio(spec[:precool_des_hr_kgpkg]) if spec[:precool_des_hr_kgpkg]
        doas.setPreheatDesignHumidityRatio(spec[:preheat_des_hr_kgpkg]) if spec[:preheat_des_hr_kgpkg]
        nil
      end

      # Place the outdoor-air-stream conditioning components (and any inline setpoint managers) on
      # the outdoor air inlet node in outboard-to-inboard order as listed. Each is added at the
      # outdoor air inlet node, which inserts it immediately downstream of the node, so the specs are
      # placed in reverse to leave the first entry outboard-most and the last nearest the served
      # loops.
      #
      # @param oa_system [OpenStudio::Model::AirLoopHVACOutdoorAirSystem] the outdoor air system
      # @param specs [Array<Hash>] the components specs
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::ModelObject, nil] the inboard-most component (its outlet feeds
      #   the served loops), or nil when there are no conditioning components
      def self.place_components(oa_system, specs, context)
        node = oa_system.outboardOANode
        return nil unless node.is_initialized

        node = node.get
        inboard = nil
        specs.reverse_each do |raw|
          entry = ComponentFactory.symbolize(raw)
          if entry[:spm_type]
            SetpointManagerFactory.build(entry, context).addToNode(node)
          else
            component = ComponentFactory.build(entry, context)
            component.addToNode(node)
            inboard ||= component
          end
        end
        inboard
      end

      # Place components on the relief air stream.
      #
      # @param oa_system [OpenStudio::Model::AirLoopHVACOutdoorAirSystem] the outdoor air system
      # @param specs [Array<Hash>] the relief_components specs
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [void]
      def self.place_relief_components(oa_system, specs, context)
        return if specs.empty?

        node = oa_system.outboardReliefNode
        unless node.is_initialized
          context.warn("relief_components on '#{oa_system.name.get}' have no relief node; skipping")
          return
        end

        node = node.get
        specs.each { |raw| ComponentFactory.build(ComponentFactory.symbolize(raw), context).addToNode(node) }
        nil
      end

      # Build and place the supply setpoint managers on the node feeding the served loops: the
      # outlet of the inboard-most conditioning component.
      #
      # @param inboard [OpenStudio::Model::ModelObject, nil] the inboard-most conditioning component
      # @param specs [Array<Hash>] the controls specs
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [void]
      def self.place_controls(inboard, specs, context)
        return if specs.empty?

        node = supply_node(inboard)
        if node.nil?
          context.warn('dedicated outdoor air system has no conditioning component to place setpoint managers after; skipping')
          return
        end

        specs.each { |spm_spec| SetpointManagerFactory.build(spm_spec, context).addToNode(node) }
        nil
      end

      # The air outlet node of a conditioning component, handling straight components
      # (+outletModelObject+) and water-to-air components (+airOutletModelObject+).
      #
      # @param component [OpenStudio::Model::ModelObject, nil] the component
      # @return [OpenStudio::Model::Node, nil] the outlet node, or nil when unavailable
      def self.supply_node(component)
        return nil if component.nil?

        outlet = component.respond_to?(:airOutletModelObject) ? component.airOutletModelObject : component.outletModelObject
        return nil unless outlet.is_initialized && outlet.get.to_Node.is_initialized

        outlet.get.to_Node.get
      end

      # Apply the availability schedule.
      #
      # @param doas [OpenStudio::Model::AirLoopHVACDedicatedOutdoorAirSystem] the dedicated OA system
      # @param availability [Hash] the availability spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [void]
      def self.apply_availability(doas, availability, context)
        doas.setAvailabilitySchedule(context.schedule(availability[:schedule_name])) if availability[:schedule_name]
        nil
      end
    end
  end
end
