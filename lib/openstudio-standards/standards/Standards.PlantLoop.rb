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

  # Apply sizing and controls to chilled water loop
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param chilled_water_loop [OpenStudio::Model::PlantLoop] chilled water loop
  # @param dsgn_sup_wtr_temp [Double] design chilled water supply T
  # @param dsgn_sup_wtr_temp_delt [Double] design chilled water supply delta T
  # @return [Boolean] returns true if successful, false if not
  def chw_sizing_control(model, chilled_water_loop, dsgn_sup_wtr_temp, dsgn_sup_wtr_temp_delt)
    # chilled water loop sizing and controls
    if dsgn_sup_wtr_temp.nil?
      dsgn_sup_wtr_temp = 44.0
      dsgn_sup_wtr_temp_c = OpenStudio.convert(dsgn_sup_wtr_temp, 'F', 'C').get
    else
      dsgn_sup_wtr_temp_c = OpenStudio.convert(dsgn_sup_wtr_temp, 'F', 'C').get
    end
    if dsgn_sup_wtr_temp_delt.nil?
      dsgn_sup_wtr_temp_delt_k = OpenStudio.convert(10.1, 'R', 'K').get
    else
      dsgn_sup_wtr_temp_delt_k = OpenStudio.convert(dsgn_sup_wtr_temp_delt, 'R', 'K').get
    end
    chilled_water_loop.setMinimumLoopTemperature(1.0)
    chilled_water_loop.setMaximumLoopTemperature(40.0)
    sizing_plant = chilled_water_loop.sizingPlant
    sizing_plant.setLoopType('Cooling')
    sizing_plant.setDesignLoopExitTemperature(dsgn_sup_wtr_temp_c)
    sizing_plant.setLoopDesignTemperatureDifference(dsgn_sup_wtr_temp_delt_k)
    chw_temp_sch = OpenstudioStandards::Schedules.create_constant_schedule_ruleset(model,
                                                                                   dsgn_sup_wtr_temp_c,
                                                                                   name: "#{chilled_water_loop.name} Temp - #{dsgn_sup_wtr_temp.round(0)}F",
                                                                                   schedule_type_limit: 'Temperature')
    chw_stpt_manager = OpenStudio::Model::SetpointManagerScheduled.new(model, chw_temp_sch)
    chw_stpt_manager.setName("#{chilled_water_loop.name} Setpoint Manager")
    chw_stpt_manager.addToNode(chilled_water_loop.supplyOutletNode)
    # @todo Yixing check the CHW Setpoint from standards
    # @todo Should be a OutdoorAirReset, see the changes I've made in Standards.PlantLoop.apply_prm_baseline_temperatures

    return true
  end

  # Set configuration in model for chilled water primary/secondary loop interface
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [String] common_pipe or heat_exchanger
  def plant_loop_set_chw_pri_sec_configuration(model)
    pri_sec_config = 'common_pipe'
    return pri_sec_config
  end

  # Determine if the plant loop is variable flow.
  # Returns true if primary and/or secondary pumps are variable speed.
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] plant loop
  # @return [Boolean] returns true if variable flow, false if not
  def plant_loop_variable_flow_system?(plant_loop)
    variable_flow = false

    # Check all the primary pumps
    plant_loop.supplyComponents.each do |sc|
      if sc.to_PumpVariableSpeed.is_initialized
        variable_flow = true
      end
    end

    # Check all the secondary pumps
    plant_loop.demandComponents.each do |sc|
      if sc.to_PumpVariableSpeed.is_initialized
        variable_flow = true
      end
    end

    return variable_flow
  end

  # Determine if temperature reset is required.
  # Required if heating or cooling capacity is greater than 300,000 Btu/hr.
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] plant loop
  # @return [Boolean] returns true if required, false if not
  def plant_loop_supply_water_temperature_reset_required?(plant_loop)
    reset_required = false

    # Not required for service water heating systems
    if plant_loop_swh_loop?(plant_loop)
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}: supply water temperature reset not required for service water heating systems.")
      return reset_required
    end

    # Not required for variable flow systems
    if plant_loop_variable_flow_system?(plant_loop)
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}: supply water temperature reset not required for variable flow systems per 6.5.4.3 Exception b.")
      return reset_required
    end

    # Determine the capacity of the system
    heating_capacity_w = plant_loop_total_heating_capacity(plant_loop)
    cooling_capacity_w = plant_loop_total_cooling_capacity(plant_loop)

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

  # Get the total cooling capacity for the plant loop
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] plant loop
  # @return [Double] total cooling capacity in watts
  def plant_loop_total_cooling_capacity(plant_loop)
    # Sum the cooling capacity for all cooling components
    # on the plant loop.
    total_cooling_capacity_w = 0
    plant_loop.supplyComponents.each do |sc|
      # ChillerElectricEIR
      if sc.to_ChillerElectricEIR.is_initialized
        chiller = sc.to_ChillerElectricEIR.get
        if chiller.referenceCapacity.is_initialized
          total_cooling_capacity_w += chiller.referenceCapacity.get
        elsif chiller.autosizedReferenceCapacity.is_initialized
          total_cooling_capacity_w += chiller.autosizedReferenceCapacity.get
        else
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.PlantLoop', "For #{plant_loop.name} capacity of #{chiller.name} is not available, total cooling capacity of plant loop will be incorrect when applying standard.")
        end
      # DistrictCooling
      elsif sc.to_DistrictCooling.is_initialized
        dist_clg = sc.to_DistrictCooling.get
        if dist_clg.nominalCapacity.is_initialized
          total_cooling_capacity_w += dist_clg.nominalCapacity.get
        elsif dist_clg.autosizedNominalCapacity.is_initialized
          total_cooling_capacity_w += dist_clg.autosizedNominalCapacity.get
        else
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.PlantLoop', "For #{plant_loop.name} capacity of DistrictCooling #{dist_clg.name} is not available, total heating capacity of plant loop will be incorrect when applying standard.")
        end
      end
    end

    total_cooling_capacity_tons = OpenStudio.convert(total_cooling_capacity_w, 'W', 'ton').get
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}, cooling capacity is #{total_cooling_capacity_tons.round} tons of refrigeration.")

    return total_cooling_capacity_w
  end

  # Get the total heating capacity for the plant loop
  #
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] plant loop
  # @return [Double] total heating capacity in watts
  # @todo Add district heating to plant loop heating capacity
  def plant_loop_total_heating_capacity(plant_loop)
    # Sum the heating capacity for all heating components
    # on the plant loop.
    total_heating_capacity_w = 0
    plant_loop.supplyComponents.each do |sc|
      if sc.to_BoilerHotWater.is_initialized
        # BoilerHotWater
        boiler = sc.to_BoilerHotWater.get
        if boiler.nominalCapacity.is_initialized
          total_heating_capacity_w += boiler.nominalCapacity.get
        elsif boiler.autosizedNominalCapacity.is_initialized
          total_heating_capacity_w += boiler.autosizedNominalCapacity.get
        else
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.PlantLoop', "For #{plant_loop.name} capacity of Boiler:HotWater ' #{boiler.name} is not available, total heating capacity of plant loop will be incorrect when applying standard.")
        end
      elsif sc.to_WaterHeaterMixed.is_initialized
        # WaterHeater:Mixed
        water_heater = sc.to_WaterHeaterMixed.get
        if water_heater.heaterMaximumCapacity.is_initialized
          total_heating_capacity_w += water_heater.heaterMaximumCapacity.get
        elsif water_heater.autosizedHeaterMaximumCapacity.is_initialized
          total_heating_capacity_w += water_heater.autosizedHeaterMaximumCapacity.get
        else
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.PlantLoop', "For #{plant_loop.name} capacity of WaterHeater:Mixed #{water_heater.name} is not available, total heating capacity of plant loop will be incorrect when applying standard.")
        end
      elsif sc.to_WaterHeaterStratified.is_initialized
        # WaterHeater:Stratified
        water_heater = sc.to_WaterHeaterStratified.get
        if water_heater.heater1Capacity.is_initialized
          total_heating_capacity_w += water_heater.heater1Capacity.get
        end
        if water_heater.heater2Capacity.is_initialized
          total_heating_capacity_w += water_heater.heater2Capacity.get
        end
      elsif sc.iddObjectType.valueName.to_s.include?('DistrictHeating')
        # DistrictHeating
        case sc.iddObjectType.valueName.to_s
        when 'OS_DistrictHeating'
          dist_htg = sc.to_DistrictHeating.get
        when 'OS_DistrictHeating_Water'
          dist_htg = sc.to_DistrictHeatingWater.get
        when 'OS_DistrictHeating_Steam'
          dist_htg = sc.to_DistrictHeatingSteam.get
        end
        if dist_htg.nominalCapacity.is_initialized
          total_heating_capacity_w += dist_htg.nominalCapacity.get
        elsif dist_htg.autosizedNominalCapacity.is_initialized
          total_heating_capacity_w += dist_htg.autosizedNominalCapacity.get
        else
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.PlantLoop', "For #{plant_loop.name} capacity of DistrictHeating #{dist_htg.name} is not available, total heating capacity of plant loop will be incorrect when applying standard.")
        end
      end
    end

    total_heating_capacity_kbtu_per_hr = OpenStudio.convert(total_heating_capacity_w, 'W', 'kBtu/hr').get
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}, heating capacity is #{total_heating_capacity_kbtu_per_hr.round} kBtu/hr.")

    return total_heating_capacity_w
  end

  # Determine the total floor area served by this loop.
  # If the loop serves a coil attached to an AirLoopHVAC,
  # count the area of all zones served by that loop.
  # If the loop serves coils inside of zone equipment,
  # count the area of the zones containing the zone equipment.
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] plant loop
  # @return [Double] floor area served in m^2
  def plant_loop_total_floor_area_served(plant_loop)
    sizing_plant = plant_loop.sizingPlant
    loop_type = sizing_plant.loopType

    # Get all the coils served by this loop
    coils = []
    case loop_type
      when 'Heating'
        plant_loop.demandComponents.each do |dc|
          if dc.to_CoilHeatingWater.is_initialized
            coils << dc.to_CoilHeatingWater.get
          end
        end
      when 'Cooling'
        plant_loop.demandComponents.each do |dc|
          if dc.to_CoilCoolingWater.is_initialized
            coils << dc.to_CoilCoolingWater.get
          end
        end
      else
        return 0.0
    end

    # The coil can either be on an airloop (as a main heating coil)
    # in an HVAC Component (like a unitary system on an airloop),
    # or in a Zone HVAC Component (like a fan coil).
    zones_served = []
    coils.each do |coil|
      if coil.airLoopHVAC.is_initialized
        air_loop = coil.airLoopHVAC.get
        zones_served += air_loop.thermalZones
      elsif coil.containingHVACComponent.is_initialized
        containing_comp = coil.containingHVACComponent.get
        if containing_comp.airLoopHVAC.is_initialized
          air_loop = containing_comp.airLoopHVAC.get
          zones_served += air_loop.thermalZones
        end
      elsif coil.containingZoneHVACComponent.is_initialized
        zone_hvac = coil.containingZoneHVACComponent.get
        if zone_hvac.thermalZone.is_initialized
          zones_served << zone_hvac.thermalZone.get
        end
      end
    end

    # Add up the area of all zones served.
    # Make sure to only add unique zones in
    # case the same zone is served by multiple
    # coils served by the same loop.  For example,
    # a HW and Reheat
    area_served_m2 = 0.0
    zones_served.uniq.each do |zone|
      area_served_m2 += zone.floorArea
    end
    area_served_ft2 = OpenStudio.convert(area_served_m2, 'm^2', 'ft^2').get

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "For #{plant_loop.name}, serves #{area_served_ft2.round} ft^2.")

    return area_served_m2
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
    cap_w = plant_loop_total_cooling_capacity(plant_loop)
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
    area_served_m2 = plant_loop_total_floor_area_served(plant_loop)
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

  # Determines the total rated watts per GPM of the loop
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] plant loop
  # @return [Double] rated power consumption per flow in watts per gpm, W*s/m^3
  def plant_loop_total_rated_w_per_gpm(plant_loop)
    sizing_plant = plant_loop.sizingPlant
    loop_type = sizing_plant.loopType

    # Supply W/GPM
    supply_w_per_gpm = 0
    demand_w_per_gpm = 0

    plant_loop.supplyComponents.each do |component|
      if component.to_PumpConstantSpeed.is_initialized
        pump = component.to_PumpConstantSpeed.get
        pump_rated_w_per_gpm = OpenstudioStandards::HVAC.pump_get_rated_w_per_gpm(pump)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "'#{loop_type}' Loop #{plant_loop.name} - Primary (Supply) Constant Speed Pump '#{pump.name}' - pump_rated_w_per_gpm #{pump_rated_w_per_gpm} W/GPM")
        supply_w_per_gpm += pump_rated_w_per_gpm
      elsif component.to_PumpVariableSpeed.is_initialized
        pump = component.to_PumpVariableSpeed.get
        pump_rated_w_per_gpm = OpenstudioStandards::HVAC.pump_get_rated_w_per_gpm(pump)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "'#{loop_type}' Loop #{plant_loop.name} - Primary (Supply) VSD Pump '#{pump.name}' - pump_rated_w_per_gpm #{pump_rated_w_per_gpm} W/GPM")
        supply_w_per_gpm += pump_rated_w_per_gpm
      end
    end

    # Determine if primary only or primary-secondary
    # IF there's a pump on the demand side it's primary-secondary
    demand_pumps = plant_loop.demandComponents('OS:Pump:VariableSpeed'.to_IddObjectType) + plant_loop.demandComponents('OS:Pump:ConstantSpeed'.to_IddObjectType)
    demand_pumps.each do |component|
      if component.to_PumpConstantSpeed.is_initialized
        pump = component.to_PumpConstantSpeed.get
        pump_rated_w_per_gpm = OpenstudioStandards::HVAC.pump_get_rated_w_per_gpm(pump)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "'#{loop_type}' Loop #{plant_loop.name} - Secondary (Demand) Constant Speed Pump '#{pump.name}' - pump_rated_w_per_gpm #{pump_rated_w_per_gpm} W/GPM")
        demand_w_per_gpm += pump_rated_w_per_gpm
      elsif component.to_PumpVariableSpeed.is_initialized
        pump = component.to_PumpVariableSpeed.get
        pump_rated_w_per_gpm = OpenstudioStandards::HVAC.pump_get_rated_w_per_gpm(pump)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "'#{loop_type}' Loop #{plant_loop.name} - Secondary (Demand) VSD Pump '#{pump.name}' - pump_rated_w_per_gpm #{pump_rated_w_per_gpm} W/GPM")
        demand_w_per_gpm += pump_rated_w_per_gpm
      end
    end

    total_rated_w_per_gpm = supply_w_per_gpm + demand_w_per_gpm

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.PlantLoop', "'#{loop_type}' Loop #{plant_loop.name} - Total #{total_rated_w_per_gpm} W/GPM - Supply #{supply_w_per_gpm} W/GPM - Demand #{demand_w_per_gpm} W/GPM")

    return total_rated_w_per_gpm
  end

  # find maximum_loop_flow_rate
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] plant loop
  # @return [Double] maximum loop flow rate in m^3/s
  def plant_loop_find_maximum_loop_flow_rate(plant_loop)
    # Get the maximum_loop_flow_rate
    maximum_loop_flow_rate = nil
    if plant_loop.maximumLoopFlowRate.is_initialized
      maximum_loop_flow_rate = plant_loop.maximumLoopFlowRate.get
    elsif plant_loop.autosizedMaximumLoopFlowRate.is_initialized
      maximum_loop_flow_rate = plant_loop.autosizedMaximumLoopFlowRate.get
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.PlantLoop', "For #{plant_loop.name} maximum loop flow rate is not available.")
    end

    return maximum_loop_flow_rate
  end

  # Determines if the loop is a Service Water Heating loop by checking if there is
  # a WaterUseConnection on the demand side or a WaterHeaterMixed on the supply side
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] plant loop
  # @return [Boolean] returns true if it is a service water heating loop, false if not
  def plant_loop_swh_loop?(plant_loop)
    serves_swh = false
    plant_loop.demandComponents.each do |comp|
      if comp.to_WaterUseConnections.is_initialized
        serves_swh = true
        break
      end
    end
    plant_loop.supplyComponents.each do |comp|
      if comp.to_WaterHeaterMixed.is_initialized
        serves_swh = true
        break
      end
    end

    # If there is a waterheater on the demand side,
    # check if the loop connected to that waterheater's
    # demand side is an swh loop itself
    plant_loop.demandComponents.each do |comp|
      if comp.to_WaterHeaterMixed.is_initialized
        comp = comp.to_WaterHeaterMixed.get
        if comp.plantLoop.is_initialized && plant_loop_swh_loop?(comp.plantLoop.get)
          serves_swh = true
          break
        end
      end
    end

    return serves_swh
  end

  # Classifies the service water system and returns information
  # about fuel types, whether it serves both heating and service water heating,
  # the water storage volume, and the total heating capacity.
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] service water heating loop
  # @return [Array<Array<String>, Bool, Double, Double>] An array of:
  #   fuel types, combination_system (true/false), storage_capacity (m^3), plant_loop_total_heating_capacity(plant_loop)  (W)
  def plant_loop_swh_system_type(plant_loop)
    combination_system = true
    storage_capacity = 0
    primary_fuels = []
    secondary_fuels = []

    # @todo to work correctly, plant_loop_total_heating_capacity(plantloop)  requires to have either hardsized capacities or a sizing run.
    primary_heating_capacity = plant_loop_total_heating_capacity(plant_loop)
    secondary_heating_capacity = 0

    plant_loop.supplyComponents.each do |component|
      # Get the object type
      obj_type = component.iddObjectType.valueName.to_s

      case obj_type
        when 'OS_DistrictHeating', 'OS_DistrictHeating_Water', 'OS_DistrictHeating_Steam'
          primary_fuels << 'DistrictHeating'
          combination_system = false
        when 'OS_HeatPump_WaterToWater_EquationFit_Heating'
          primary_fuels << 'Electricity'
        when 'OS_SolarCollector_FlatPlate_PhotovoltaicThermal', 'OS_SolarCollector_FlatPlate_Water', 'OS_SolarCollector_IntegralCollectorStorage'
          primary_fuels << 'SolarEnergy'
        when 'OS_WaterHeater_HeatPump'
          primary_fuels << 'Electricity'
        when 'OS_WaterHeater_Mixed'
          component = component.to_WaterHeaterMixed.get
          # Check it it's actually a heater, not just a storage tank
          if component.heaterMaximumCapacity.empty? || component.heaterMaximumCapacity.get != 0
            # If it does, we add the heater Fuel Type
            primary_fuels << component.heaterFuelType
            # And in this case we'll reuse this object
            combination_system = false
          end
          # @todo not sure about whether it should be an elsif or not
          # Check the plant loop connection on the source side
          if component.secondaryPlantLoop.is_initialized
            source_plant_loop = component.secondaryPlantLoop.get

            # error if Loop heating fuels method is not available
            if component.model.version < OpenStudio::VersionString.new('3.6.0')
              OpenStudio.logFree(OpenStudio::Error, 'openstudio.Standards.PlantLoop', 'Required Loop method .heatingFuelTypes is not available in pre-OpenStudio 3.6.0 versions. Use a more recent version of OpenStudio.')
            end

            secondary_fuels += source_plant_loop.heatingFuelTypes.map(&:valueName)
            secondary_heating_capacity += plant_loop_total_heating_capacity(source_plant_loop)
          end

          # Storage capacity
          if component.tankVolume.is_initialized
            storage_capacity = component.tankVolume.get
          end

        when 'OS_WaterHeater_Stratified'
          component = component.to_WaterHeaterStratified.get

          # Check if the heater actually has a capacity (otherwise it's simply a Storage Tank)
          if component.heaterMaximumCapacity.empty? || component.heaterMaximumCapacity.get != 0
            # If it does, we add the heater Fuel Type
            primary_fuels << component.heaterFuelType
            # And in this case we'll reuse this object
            combination_system = false
          end
          # @todo not sure about whether it should be an elsif or not
          # Check the plant loop connection on the source side
          if component.secondaryPlantLoop.is_initialized
            source_plant_loop = component.secondaryPlantLoop.get

            # error if Loop heating fuels method is not available
            if component.model.version < OpenStudio::VersionString.new('3.6.0')
              OpenStudio.logFree(OpenStudio::Error, 'openstudio.Standards.PlantLoop', 'Required Loop method .heatingFuelTypes is not available in pre-OpenStudio 3.6.0 versions. Use a more recent version of OpenStudio.')
            end

            secondary_fuels += source_plant_loop.heatingFuelTypes.map(&:valueName)
            secondary_heating_capacity += plant_loop_total_heating_capacity(source_plant_loop)
          end

          # Storage capacity
          if component.tankVolume.is_initialized
            storage_capacity = component.tankVolume.get
          end

        when 'OS_HeatExchanger_FluidToFluid'
          hx = component.to_HeatExchangerFluidToFluid.get
          cooling_hx_control_types = ['CoolingSetpointModulated', 'CoolingSetpointOnOff', 'CoolingDifferentialOnOff', 'CoolingSetpointOnOffWithComponentOverride']
          cooling_hx_control_types.each(&:downcase!)
          if !cooling_hx_control_types.include?(hx.controlType.downcase) && hx.secondaryPlantLoop.is_initialized
            source_plant_loop = hx.secondaryPlantLoop.get

            # error if Loop heating fuels method is not available
            if component.model.version < OpenStudio::VersionString.new('3.6.0')
              OpenStudio.logFree(OpenStudio::Error, 'openstudio.Standards.PlantLoop', 'Required Loop method .heatingFuelTypes is not available in pre-OpenStudio 3.6.0 versions. Use a more recent version of OpenStudio.')
            end

            secondary_fuels += source_plant_loop.heatingFuelTypes.map(&:valueName)
            secondary_heating_capacity += plant_loop_total_heating_capacity(source_plant_loop)
          end

        when 'OS_Node', 'OS_Pump_ConstantSpeed', 'OS_Pump_VariableSpeed', 'OS_Connector_Splitter', 'OS_Connector_Mixer', 'OS_Pipe_Adiabatic'
        # To avoid extraneous debug messages
      end
    end

    # @todo decide how to handle primary and secondary stuff
    fuels = primary_fuels + secondary_fuels
    total_heating_capacity = primary_heating_capacity + secondary_heating_capacity
    # If the primary heating capacity is bigger than secondary, assume the secondary is just a backup and disregard it?
    # if primary_heating_capacity > secondary_heating_capacity
    #   plant_loop_total_heating_capacity(plant_loop)  = primary_heating_capacity
    #   fuels = primary_fuels
    # end

    return fuels.uniq.sort, combination_system, storage_capacity, total_heating_capacity
  end

  # This method calculates the capacity of a plant loop by multiplying the temp difference across the loop, the maximum flow rate,
  # the fluid density, and the fluid heat capacity (currently only works with water).  This may be a little more approximate than the
  # heating and cooling capacity methods described above however is not limited to certain types of equipment and can be used for
  # condensing plant loops too.
  #
  # @param plant_loop [OpenStudio::Model::PlantLoop] plant loop
  # @return [Double] capacity of plant loop in watts
  def plant_loop_capacity_w_by_maxflow_and_delta_t_forwater(plant_loop)
    plantloop_maxflowrate = nil
    if plant_loop.fluidType != 'Water'
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.PlantLoop', "The fluid used in the plant loop named #{plant_loop.name} is not water.  The current version of this method only calculates the capacity of plant loops that use water.")
    end
    plantloop_maxflowrate = plant_loop_find_maximum_loop_flow_rate(plant_loop)
    plantloop_dt = plant_loop.sizingPlant.loopDesignTemperatureDifference.to_f
    # Plant loop capacity = temperature difference across plant loop * maximum plant loop flow rate * density of water (1000 kg/m^3) * see next line
    # Heat capacity of water (4180 J/(kg*K))
    plantloop_capacity = plantloop_dt * plantloop_maxflowrate * 1000.0 * 4180.0
    return plantloop_capacity
  end

end
