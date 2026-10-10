module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Creator:PlantLoopBuilder
    # Builds a PlantLoop from a creator spec.
    #
    # This is the system layer: it calls the component factory to build each component
    # disconnected, then owns all connection — placing components on the supply inlet, parallel
    # branches, and supply outlet, connecting demand-side equipment, and placing the loop setpoint
    # managers. See the two-layer architecture in the implementation plan.
    module PlantLoopBuilder
      # Build a plant loop and connect its components.
      #
      # @param spec [Hash] a plantLoop spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [OpenStudio::Model::PlantLoop] the connected loop
      def self.build(spec, context)
        spec = ComponentFactory.deep_symbolize(spec)
        loop = OpenStudio::Model::PlantLoop.new(context.model)
        loop.setName(spec[:name]) if spec[:name]

        apply_sizing(loop, spec[:design_info] || {})
        apply_loop_settings(loop, spec)

        place_series_on_node(build_all(spec[:supply_inlet_components], context), loop.supplyInletNode)
        (spec[:supply_branches] || []).each { |branch| place_branch(loop, build_all(branch, context)) }
        place_series_on_node(build_all(spec[:supply_outlet_components], context), loop.supplyOutletNode)
        build_all(spec[:demand_components], context).each { |component| loop.addDemandBranchForComponent(component) }
        place_series_on_node(build_all(spec[:demand_inlet_components], context), loop.demandInletNode)

        add_loop_pipes(loop, context, spec[:supply_bypass_name], spec[:demand_bypass_name])
        place_controls(loop, spec[:controls] || [], context)
        apply_ground_hx(loop, spec, context) if spec[:ground_hx_loop]

        context.register_plant_loop(loop.name.get, loop)
        build_secondary_loop(loop, spec[:secondary_loop], context) if spec[:secondary_loop]
        loop
      end

      # Apply SizingPlant fields from the design_info.
      #
      # @param loop [OpenStudio::Model::PlantLoop] the loop
      # @param design [Hash] the design_info spec
      # @return [void]
      def self.apply_sizing(loop, design)
        sizing = loop.sizingPlant
        sizing.setLoopType(design[:loop_type]) if design[:loop_type]
        exit_temp = Quantities.resolve(design, 'supply_temp', :temperature)
        sizing.setDesignLoopExitTemperature(exit_temp) unless exit_temp.nil?
        delta = Quantities.resolve(design, 'temp_delta', :temperature_difference)
        sizing.setLoopDesignTemperatureDifference(delta) unless delta.nil?
        sizing.setSizingOption(design[:sizing_option]) if design[:sizing_option]
        sizing.setZoneTimestepsinAveragingWindow(design[:averaging_window]) if design[:averaging_window]
        sizing.setCoincidentSizingFactorMode(design[:coincident_sizing_factor_mode]) if design[:coincident_sizing_factor_mode]
        nil
      end

      # Apply fluid, load distribution, and temperature-limit fields to the loop.
      #
      # @param loop [OpenStudio::Model::PlantLoop] the loop
      # @param spec [Hash] the plantLoop spec
      # @return [void]
      def self.apply_loop_settings(loop, spec)
        loop.setFluidType(spec[:fluid_type]) if spec[:fluid_type]
        loop.setGlycolConcentration((spec[:glycol_percent] * 100).round) if spec[:glycol_percent]
        loop.setLoadDistributionScheme(spec[:load_distribution_scheme]) if spec[:load_distribution_scheme]
        loop.setCommonPipeSimulation(spec[:common_pipe_sim]) if spec[:common_pipe_sim]
        min_temp = Quantities.resolve(spec, 'min_loop_temp', :temperature)
        loop.setMinimumLoopTemperature(min_temp) unless min_temp.nil?
        max_temp = Quantities.resolve(spec, 'max_loop_temp', :temperature)
        loop.setMaximumLoopTemperature(max_temp) unless max_temp.nil?
        nil
      end

      # Add the standard adiabatic bypass and connecting pipes a plant loop needs: a supply-equipment
      # bypass branch, a demand (coil) bypass branch, and supply-outlet, demand-inlet, and
      # demand-outlet pipes. Names follow the loop name so a built loop matches the conventional
      # topology.
      #
      # @param loop [OpenStudio::Model::PlantLoop] the loop
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @param supply_bypass_name [String, nil] name for the supply-equipment bypass pipe
      # @param demand_bypass_name [String, nil] name for the demand (coil) bypass pipe
      # @return [void]
      def self.add_loop_pipes(loop, context, supply_bypass_name = nil, demand_bypass_name = nil)
        name = loop.name.get

        supply_bypass = OpenStudio::Model::PipeAdiabatic.new(context.model)
        supply_bypass.setName(supply_bypass_name || "#{name} Supply Equipment Bypass")
        loop.addSupplyBranchForComponent(supply_bypass)

        coil_bypass = OpenStudio::Model::PipeAdiabatic.new(context.model)
        coil_bypass.setName(demand_bypass_name || "#{name} Coil Bypass")
        loop.addDemandBranchForComponent(coil_bypass)

        supply_outlet = OpenStudio::Model::PipeAdiabatic.new(context.model)
        supply_outlet.setName("#{name} Supply Outlet")
        supply_outlet.addToNode(loop.supplyOutletNode)

        demand_inlet = OpenStudio::Model::PipeAdiabatic.new(context.model)
        demand_inlet.setName("#{name} Demand Inlet")
        demand_inlet.addToNode(loop.demandInletNode)

        demand_outlet = OpenStudio::Model::PipeAdiabatic.new(context.model)
        demand_outlet.setName("#{name} Demand Outlet")
        demand_outlet.addToNode(loop.demandOutletNode)
        nil
      end

      # Build every component in a list via the component factory.
      #
      # @param specs [Array<Hash>, nil] component specs
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [Array<OpenStudio::Model::ModelObject>] the built components
      def self.build_all(specs, context)
        (specs || []).map { |component_spec| ComponentFactory.build(component_spec, context) }
      end

      # Place components in series starting at a node.
      #
      # @param components [Array<OpenStudio::Model::ModelObject>] the components, in flow order
      # @param node [OpenStudio::Model::Node] the starting node
      # @return [void]
      def self.place_series_on_node(components, node)
        return if components.empty?

        components.first.addToNode(node)
        components.each_cons(2) do |upstream, downstream|
          downstream.addToNode(upstream.outletModelObject.get.to_Node.get)
        end
        nil
      end

      # Place a parallel supply branch, with its components in series along the branch.
      #
      # @param loop [OpenStudio::Model::PlantLoop] the loop
      # @param components [Array<OpenStudio::Model::ModelObject>] the branch components, in flow order
      # @return [void]
      def self.place_branch(loop, components)
        return if components.empty?
        # a self-placing component (e.g. AirSourceHeatPump) already added itself to the loop
        return if components.size == 1 && already_on_plant_loop?(components.first)

        loop.addSupplyBranchForComponent(components.first)
        components.each_cons(2) do |upstream, downstream|
          downstream.addToNode(upstream.outletModelObject.get.to_Node.get)
        end
        nil
      end

      # Whether a component has already been connected to a plant loop (it self-placed).
      #
      # @param component [OpenStudio::Model::ModelObject] the component
      # @return [Boolean] true when the component is already on a plant loop
      def self.already_on_plant_loop?(component)
        component.respond_to?(:plantLoop) && component.plantLoop.is_initialized
      end

      # Build and place the loop setpoint managers. The default node is the supply outlet; a
      # +spm_node+ override targets a named supply component's outlet (see {SetpointManagerFactory.place}).
      #
      # @param loop [OpenStudio::Model::PlantLoop] the loop
      # @param specs [Array<Hash>] the controls specs
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [void]
      def self.place_controls(loop, specs, context)
        specs.each do |spm_spec|
          manager = SetpointManagerFactory.build(spm_spec, context)
          SetpointManagerFactory.place(manager, spm_spec, loop, loop.supplyOutletNode, context)
        end
        nil
      end

      # Drive a loop's temperature-source component from its inlet temperature using EMS, so the
      # loop mimics a ground heat exchanger. The source outlet temperature follows a linear reset
      # off the loop inlet temperature (Tout = slope * Tin + intercept); the slope and intercept are
      # derived from a control-temperature envelope, all of which +ems_params+ may override.
      #
      # @param loop [OpenStudio::Model::PlantLoop] the loop
      # @param spec [Hash] the plantLoop spec
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [void]
      def self.apply_ground_hx(loop, spec, context)
        source = loop.supplyComponents.map { |c| c.to_PlantComponentTemperatureSource }.find(&:is_initialized)
        if source.nil?
          context.warn("ground_hx_loop '#{loop.name.get}' has no PlantComponentTemperatureSource; skipping the ground heat exchanger EMS")
          return
        end
        source = source.get

        slope, intercept = ground_hx_reset(spec[:ems_params] || {})
        schedule = ground_hx_source_schedule(source, context.model)
        install_ground_hx_ems(loop, source, schedule, slope, intercept, context)
        nil
      end

      # Resolve the linear reset (slope, intercept) for the ground heat exchanger outlet
      # temperature from the ems_params control-temperature envelope, with typical defaults.
      #
      # @param params [Hash] the ems_params spec
      # @return [Array(Float, Float)] the slope (C per C) and intercept (C)
      def self.ground_hx_reset(params)
        return [params[:slope].to_f, params[:intercept].to_f] if params[:slope] && params[:intercept]

        min_inlet = Quantities.resolve(params, 'min_inlet_temp', :temperature) || 10.0
        max_inlet = Quantities.resolve(params, 'max_inlet_temp', :temperature) || 35.0
        min_outlet = Quantities.resolve(params, 'min_outlet_temp', :temperature) || 10.0
        max_outlet = Quantities.resolve(params, 'max_outlet_temp', :temperature) || 24.0
        slope = (max_outlet - min_outlet) / (max_inlet - min_inlet)
        [slope, min_outlet - (slope * min_inlet)]
      end

      # The actuatable source-temperature schedule for a temperature source: its existing constant
      # schedule if it has one, otherwise a new Schedule:Constant assigned to it and to a supply
      # outlet setpoint manager on the source's own outlet.
      #
      # @param source [OpenStudio::Model::PlantComponentTemperatureSource] the temperature source
      # @param model [OpenStudio::Model::Model] the model
      # @return [OpenStudio::Model::ScheduleConstant] the schedule
      def self.ground_hx_source_schedule(source, model)
        existing = source.sourceTemperatureSchedule
        return existing.get.to_ScheduleConstant.get if existing.is_initialized && existing.get.to_ScheduleConstant.is_initialized

        schedule = OpenStudio::Model::ScheduleConstant.new(model)
        schedule.setName("#{source.name.get} Temperature Schedule")
        schedule.setValue(24.0)
        source.setTemperatureSpecificationType('Scheduled')
        source.setSourceTemperatureSchedule(schedule)
        if source.outletModelObject.is_initialized
          manager = OpenStudio::Model::SetpointManagerScheduled.new(model, schedule)
          manager.setName("#{source.name.get} Outlet Setpoint")
          manager.addToNode(source.outletModelObject.get.to_Node.get)
        end
        schedule
      end

      # Install the EMS sensor, actuator, program, and calling manager that drive the ground heat
      # exchanger source schedule from the loop inlet temperature.
      #
      # @param loop [OpenStudio::Model::PlantLoop] the loop
      # @param source [OpenStudio::Model::PlantComponentTemperatureSource] the temperature source
      # @param schedule [OpenStudio::Model::ScheduleConstant] the actuated source schedule
      # @param slope [Float] the reset slope (C per C)
      # @param intercept [Float] the reset intercept (C)
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [void]
      def self.install_ground_hx_ems(loop, source, schedule, slope, intercept, context)
        name = OpenstudioStandards::HVAC.ems_friendly_name(source.name.get)
        model = context.model

        inlet_sensor = OpenStudio::Model::EnergyManagementSystemSensor.new(model, 'System Node Temperature')
        inlet_sensor.setName("#{name} Inlet Temp Sensor")
        inlet_sensor.setKeyName(loop.supplyInletNode.handle.to_s)

        actuator = OpenStudio::Model::EnergyManagementSystemActuator.new(schedule, 'Schedule:Constant', 'Schedule Value')
        actuator.setName("#{name} Outlet Temp Actuator")

        program = OpenStudio::Model::EnergyManagementSystemProgram.new(model)
        program.setName("#{name} Temperature Control")
        program.setBody(<<-EMS)
          SET Tin = #{inlet_sensor.handle}
          SET Tout = #{slope.round(3)} * Tin + #{intercept.round(2)}
          SET #{actuator.handle} = Tout
        EMS

        calling_manager = OpenStudio::Model::EnergyManagementSystemProgramCallingManager.new(model)
        calling_manager.setName("#{program.name.get} Calling Manager")
        calling_manager.setCallingPoint('InsideHVACSystemIterationLoop')
        calling_manager.addProgram(program)
        nil
      end

      # Build the secondary distribution loop and join it to this primary loop per its
      # +interconnection+ object (a fluid-to-fluid heat exchanger, or a common pipe).
      #
      # @param primary [OpenStudio::Model::PlantLoop] the primary loop
      # @param secondary_spec [Hash] the secondary_loop spec (carries its own interconnection)
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [void]
      def self.build_secondary_loop(primary, secondary_spec, context)
        secondary_spec = ComponentFactory.deep_symbolize(secondary_spec)
        secondary = build(secondary_spec, context)
        interconnection = secondary_spec[:interconnection]
        if interconnection.nil?
          context.warn("secondary loop '#{secondary.name.get}' has no interconnection; it is not joined to '#{primary.name.get}'")
          return
        end

        case interconnection[:type]
        when 'heat_exchanger'
          join_by_heat_exchanger(primary, secondary, interconnection[:hx] || {}, context)
        when 'common_pipe'
          primary.setCommonPipeSimulation('CommonPipe')
        else
          context.warn("secondary loop interconnection type '#{interconnection[:type]}' is not supported")
        end
        nil
      end

      # Join a secondary loop to its primary with a fluid-to-fluid heat exchanger: the exchanger sits
      # on the secondary loop's supply side (its heat source) and on the primary loop's demand side
      # (drawing from the primary). Adiabatic bypass and outlet pipes complete the secondary supply.
      #
      # @param primary [OpenStudio::Model::PlantLoop] the primary loop
      # @param secondary [OpenStudio::Model::PlantLoop] the secondary loop
      # @param hx_spec [Hash] the heat exchanger spec (hxFluidToFluidObj)
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @return [void]
      def self.join_by_heat_exchanger(primary, secondary, hx_spec, context)
        hx = ComponentFactory.build(hx_spec.merge(obj_type: 'HeatExchangerFluidToFluid'), context)
        secondary.addSupplyBranchForComponent(hx)
        primary.addDemandBranchForComponent(hx)

        bypass = OpenStudio::Model::PipeAdiabatic.new(context.model)
        bypass.setName("#{secondary.name.get} HX Bypass")
        secondary.addSupplyBranchForComponent(bypass)
        outlet = OpenStudio::Model::PipeAdiabatic.new(context.model)
        outlet.setName("#{secondary.name.get} Supply Outlet")
        outlet.addToNode(secondary.supplyOutletNode)
        nil
      end
    end
  end
end
