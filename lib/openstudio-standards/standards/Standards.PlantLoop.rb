class Standard
  # @!group PlantLoop

  # Apply all standard required controls to the plant loop
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] plant loop
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [Boolean] returns true if successful, false if not
  def plant_loop_apply_standard_controls(plant_loop, climate_zone)
    # Supply water temperature reset
    # plant_loop_enable_supply_water_temperature_reset(plant_loop) if plant_loop_supply_water_temperature_reset_required?(plant_loop)
  end

  # Determine if temperature reset is required.
  # Required if heating or cooling capacity is greater than 300,000 Btu/hr.
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] plant loop
  # @return [Boolean] returns true if required, false if not
  def plant_loop_supply_water_temperature_reset_required?(plant_loop)
    reset_required = false

    # Not required for service water heating systems
    if OpenstudioStandards::HVAC.plant_loop_swh_loop?(plant_loop)
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}: supply water temperature reset not required for service water heating systems.")
      return reset_required
    end

    # Not required for variable flow systems
    if OpenstudioStandards::HVAC.plant_loop_variable_flow_system?(plant_loop)
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}: supply water temperature reset not required for variable flow systems per 6.5.4.3 Exception b.")
      return reset_required
    end

    # Determine the capacity of the system
    heating_capacity_w = OpenstudioStandards::HVAC.plant_loop_total_heating_capacity(plant_loop)
    cooling_capacity_w = OpenstudioStandards::HVAC.plant_loop_total_cooling_capacity(plant_loop)

    heating_capacity_btu_per_hr = OpenStudio.convert(heating_capacity_w, 'W', 'Btu/hr').get
    cooling_capacity_btu_per_hr = OpenStudio.convert(cooling_capacity_w, 'W', 'Btu/hr').get

    # Compare against capacity minimum requirement
    min_cap_btu_per_hr = 300_000
    if heating_capacity_btu_per_hr > min_cap_btu_per_hr
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}: supply water temperature reset is required because heating capacity of #{heating_capacity_btu_per_hr.round} Btu/hr exceeds the minimum threshold of #{min_cap_btu_per_hr.round} Btu/hr.")
      reset_required = true
    elsif cooling_capacity_btu_per_hr > min_cap_btu_per_hr
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}: supply water temperature reset is required because cooling capacity of #{cooling_capacity_btu_per_hr.round} Btu/hr exceeds the minimum threshold of #{min_cap_btu_per_hr.round} Btu/hr.")
      reset_required = true
    else
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}: supply water temperature reset is not required because capacity is less than minimum of #{min_cap_btu_per_hr.round} Btu/hr.")
    end

    return reset_required
  end

  # Enable reset of hot or chilled water temperature based on outdoor air temperature.
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] plant loop
  # @return [Boolean] returns true if successful, false if not
  def plant_loop_enable_supply_water_temperature_reset(plant_loop)
    # Get the current setpoint manager on the outlet node
    # and determine if already has temperature reset
    spms = plant_loop.supplyOutletNode.setpointManagers
    spms.each do |spm|
      if spm.to_SetpointManagerOutdoorAirReset.is_initialized
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}: supply water temperature reset is already enabled.")
        return false
      end
    end

    # Get the design water temperature
    sizing_plant = plant_loop.sizingPlant
    design_temp_c = sizing_plant.designLoopExitTemperature
    design_temp_f = OpenStudio.convert(design_temp_c, 'C', 'F').get
    loop_type = sizing_plant.loopType

    # Apply the reset, depending on the type of loop.
    case loop_type
      when 'Heating'

        # Hot water as-designed when cold outside
        hwt_at_lo_oat_f = design_temp_f
        hwt_at_lo_oat_c = OpenStudio.convert(hwt_at_lo_oat_f, 'F', 'C').get
        # 30F decrease when it's hot outside,
        # and therefore less heating capacity is likely required.
        decrease_f = 30.0
        hwt_at_hi_oat_f = hwt_at_lo_oat_f - decrease_f
        hwt_at_hi_oat_c = OpenStudio.convert(hwt_at_hi_oat_f, 'F', 'C').get

        # Define the high and low outdoor air temperatures
        lo_oat_f = 20
        lo_oat_c = OpenStudio.convert(lo_oat_f, 'F', 'C').get
        hi_oat_f = 50
        hi_oat_c = OpenStudio.convert(hi_oat_f, 'F', 'C').get

        # Create a setpoint manager
        hwt_oa_reset = OpenStudio::Model::SetpointManagerOutdoorAirReset.new(plant_loop.model)
        hwt_oa_reset.setName("#{plant_loop.name} HW Temp Reset")
        hwt_oa_reset.setControlVariable('Temperature')
        hwt_oa_reset.setSetpointatOutdoorLowTemperature(hwt_at_lo_oat_c)
        hwt_oa_reset.setOutdoorLowTemperature(lo_oat_c)
        hwt_oa_reset.setSetpointatOutdoorHighTemperature(hwt_at_hi_oat_c)
        hwt_oa_reset.setOutdoorHighTemperature(hi_oat_c)
        hwt_oa_reset.addToNode(plant_loop.supplyOutletNode)

        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}: hot water temperature reset from #{hwt_at_lo_oat_f.round}F to #{hwt_at_hi_oat_f.round}F between outdoor air temps of #{lo_oat_f.round}F and #{hi_oat_f.round}F.")

      when 'Cooling'

        # Chilled water as-designed when hot outside
        chwt_at_hi_oat_f = design_temp_f
        chwt_at_hi_oat_c = OpenStudio.convert(chwt_at_hi_oat_f, 'F', 'C').get
        # 10F increase when it's cold outside,
        # and therefore less cooling capacity is likely required.
        increase_f = 10.0
        chwt_at_lo_oat_f = chwt_at_hi_oat_f + increase_f
        chwt_at_lo_oat_c = OpenStudio.convert(chwt_at_lo_oat_f, 'F', 'C').get

        # Define the high and low outdoor air temperatures
        lo_oat_f = 60
        lo_oat_c = OpenStudio.convert(lo_oat_f, 'F', 'C').get
        hi_oat_f = 80
        hi_oat_c = OpenStudio.convert(hi_oat_f, 'F', 'C').get

        # Create a setpoint manager
        chwt_oa_reset = OpenStudio::Model::SetpointManagerOutdoorAirReset.new(plant_loop.model)
        chwt_oa_reset.setName("#{plant_loop.name} CHW Temp Reset")
        chwt_oa_reset.setControlVariable('Temperature')
        chwt_oa_reset.setSetpointatOutdoorLowTemperature(chwt_at_lo_oat_c)
        chwt_oa_reset.setOutdoorLowTemperature(lo_oat_c)
        chwt_oa_reset.setSetpointatOutdoorHighTemperature(chwt_at_hi_oat_c)
        chwt_oa_reset.setOutdoorHighTemperature(hi_oat_c)
        chwt_oa_reset.addToNode(plant_loop.supplyOutletNode)

        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}: chilled water temperature reset from #{chwt_at_hi_oat_f.round}F to #{chwt_at_lo_oat_f.round}F between outdoor air temps of #{hi_oat_f.round}F and #{lo_oat_f.round}F.")

      else

        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}: cannot enable supply water temperature reset for a #{loop_type} loop.")
        return false
    end
    return true
  end

  # Applies the pumping controls to the loop based on Appendix G.
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] plant loop
  # @return [Boolean] returns true if successful, false if not
  def plant_loop_apply_prm_baseline_pumping_type(plant_loop)
    sizing_plant = plant_loop.sizingPlant
    loop_type = sizing_plant.loopType

    case loop_type
      when 'Heating'
        plant_loop_apply_prm_baseline_hot_water_pumping_type(plant_loop)
      when 'Cooling'
        plant_loop_apply_prm_baseline_chilled_water_pumping_type(plant_loop)
      when 'Condenser'
        plant_loop_apply_prm_baseline_condenser_water_pumping_type(plant_loop)
    end

    return true
  end

  # Applies the chilled water pumping controls to the loop based on Appendix G.
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] chilled water loop
  # @return [Boolean] returns true if successful, false if not
  def plant_loop_apply_prm_baseline_chilled_water_pumping_type(plant_loop)
    # Determine the pumping type.
    minimum_cap_tons = 300.0

    # Determine the capacity
    cap_w = OpenstudioStandards::HVAC.plant_loop_total_cooling_capacity(plant_loop)
    cap_tons = OpenStudio.convert(cap_w, 'W', 'ton').get

    # Determine if it a district cooling system
    has_district_cooling = false
    plant_loop.supplyComponents.each do |sc|
      if sc.to_DistrictCooling.is_initialized
        has_district_cooling = true
      end
    end

    # Determine the primary and secondary pumping types
    pri_control_type = nil
    sec_control_type = nil
    if has_district_cooling
      pri_control_type = if cap_tons > minimum_cap_tons
                           'VSD No Reset'
                         else
                           'Riding Curve'
                         end
    else
      pri_control_type = 'Constant Flow'
      sec_control_type = if cap_tons > minimum_cap_tons
                           'VSD No Reset'
                         else
                           'Riding Curve'
                         end
    end

    # Report out the pumping type
    unless pri_control_type.nil?
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}, primary pump type is #{pri_control_type}.")
    end

    unless sec_control_type.nil?
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}, secondary pump type is #{sec_control_type}.")
    end

    # Modify all the primary pumps
    plant_loop.supplyComponents.each do |sc|
      if sc.to_PumpVariableSpeed.is_initialized
        pump = sc.to_PumpVariableSpeed.get
        OpenstudioStandards::HVAC.pump_variable_speed_set_control_type(pump, control_type: pri_control_type)
      elsif sc.to_HeaderedPumpsVariableSpeed.is_initialized
        pump = sc.to_HeaderedPumpsVariableSpeed.get
        OpenstudioStandards::HVAC.pump_variable_speed_set_control_type(pump, control_type: pri_control_type)
      end
    end

    # Modify all the secondary pumps besides constant pumps
    plant_loop.demandComponents.each do |sc|
      if sc.to_PumpVariableSpeed.is_initialized
        pump = sc.to_PumpVariableSpeed.get
        OpenstudioStandards::HVAC.pump_variable_speed_set_control_type(pump, control_type: sec_control_type)
      elsif sc.to_HeaderedPumpsVariableSpeed.is_initialized
        pump = sc.to_HeaderedPumpsVariableSpeed.get
        OpenstudioStandards::HVAC.pump_variable_speed_set_control_type(pump, control_type: sec_control_type)
      end
    end

    return true
  end

  # Applies the hot water pumping controls to the loop based on Appendix G.
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] hot water loop
  # @return [Boolean] returns true if successful, false if not
  def plant_loop_apply_prm_baseline_hot_water_pumping_type(plant_loop)
    # Determine the minimum area to determine
    # pumping type.
    minimum_area_ft2 = 120_000

    # Determine the area served
    area_served_m2 = OpenstudioStandards::HVAC.plant_loop_total_floor_area_served(plant_loop)
    area_served_ft2 = OpenStudio.convert(area_served_m2, 'm^2', 'ft^2').get

    # Determine the pump type
    control_type = 'Riding Curve'
    if area_served_ft2 > minimum_area_ft2
      control_type = 'VSD No Reset'
    end

    # Modify all the primary pumps
    plant_loop.supplyComponents.each do |sc|
      if sc.to_PumpVariableSpeed.is_initialized
        pump = sc.to_PumpVariableSpeed.get
        OpenstudioStandards::HVAC.pump_variable_speed_set_control_type(pump, control_type: control_type)
      end
    end

    # Report out the pumping type
    unless control_type.nil?
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}, pump type is #{control_type}.")
    end

    return true
  end

  # Applies the condenser water pumping controls to the loop based on Appendix G.
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] condenser water loop
  # @return [Boolean] returns true if successful, false if not
  def plant_loop_apply_prm_baseline_condenser_water_pumping_type(plant_loop)
    # All condenser water loops are constant flow
    control_type = 'Constant Flow'

    # Report out the pumping type
    unless control_type.nil?
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}, pump type is #{control_type}.")
    end

    # Modify all primary pumps
    plant_loop.supplyComponents.each do |sc|
      if sc.to_PumpVariableSpeed.is_initialized
        pump = sc.to_PumpVariableSpeed.get
        OpenstudioStandards::HVAC.pump_variable_speed_set_control_type(pump, control_type: control_type)
      elsif sc.to_HeaderedPumpsVariableSpeed.is_initialized
        pump = sc.to_HeaderedPumpsVariableSpeed.get
        OpenstudioStandards::HVAC.pump_variable_speed_set_control_type(pump, control_type: control_type)
      end
    end

    return true
  end

end
