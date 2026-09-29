class Standard
  # @!group CoilCoolingDXSingleSpeed

  include CoilDX

  # Finds lookup object in standards and return efficiency
  #
  # @param coil_cooling_dx_single_speed [OpenStudio::Model::CoilCoolingDXSingleSpeed] coil cooling dx single speed object
  # @param rename [Boolean] if true, object will be renamed to include capacity and efficiency level
  # @param equipment_type [Boolean] indicate that equipment_type should be in the search criteria.
  # @return [Double] full load efficiency (COP)
  def coil_cooling_dx_single_speed_standard_minimum_cop(coil_cooling_dx_single_speed, rename = false, equipment_type = false)
    search_criteria = coil_dx_find_search_criteria(coil_cooling_dx_single_speed, equipment_type)
    cooling_type = search_criteria['cooling_type']
    heating_type = search_criteria['heating_type']
    sub_category = search_criteria['subcategory']
    equipment_type = nil

    # Define database
    if OpenstudioStandards::HVAC.coil_dx_heat_pump?(coil_cooling_dx_single_speed)
      database = standards_data['heat_pumps']
    else
      database = standards_data['unitary_acs']
    end


    # Additional search criteria
    if database[0].keys.include?('equipment_type')
      if search_criteria.keys.include?('equipment_type')
        equipment_type = search_criteria['equipment_type']
        if ['PTAC', 'PTHP'].include?(equipment_type) && template.include?('90.1')
          search_criteria['application'] = coil_dx_packaged_terminal_application(coil_cooling_dx_single_speed)
        end
      elsif !OpenstudioStandards::HVAC.coil_dx_heat_pump?(coil_cooling_dx_single_speed)
        search_criteria['equipment_type'] = 'Air Conditioners'
      end
    end
    if database[0].keys.include?('region')
      search_criteria['region'] = nil # non-nil values are currently used for residential products
    end

    if ['PTAC', 'PTHP'].include?(equipment_type) || ['PTAC', 'PTHP'].include?(OpenstudioStandards::HVAC.coil_dx_subcategory(coil_cooling_dx_single_speed))
      thermal_zone = OpenstudioStandards::HVAC.hvac_component_get_thermal_zone(coil_cooling_dx_single_speed)
      multiplier = thermal_zone.multiplier if !thermal_zone.nil?
    end
    # Get the capacity
    capacity_w = OpenstudioStandards::HVAC.coil_cooling_dx_single_speed_get_capacity(coil_cooling_dx_single_speed, multiplier: multiplier)
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
    capacity_kbtu_per_hr = OpenStudio.convert(capacity_w, 'W', 'kBtu/hr').get

    # Look up the efficiency characteristics
    # Lookup efficiencies depending on whether it is a unitary AC or a heat pump
    ac_props = nil
    ac_props = model_find_object(database, search_criteria, capacity_btu_per_hr, Date.today)
    # Check to make sure properties were found
    if ac_props.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{coil_cooling_dx_single_speed.name}, cannot find efficiency info using #{search_criteria} and capacity #{capacity_btu_per_hr} btu/hr, cannot apply efficiency standard.")
      return false
    end

    # Get the minimum efficiency standards
    cop = nil

    # If PTHP, use equations if coefficients are specified
    # Check both new format (equipment_type == 'PTHP') and old format (e.g. DOE Ref Pre-1980 / 1980-2004)
    # where there is no 'equipment_type' key and PTHP is identified via subcategory instead.
    pthp_eer_coeff_1 = ac_props['pthp_eer_coefficient_1']
    pthp_eer_coeff_2 = ac_props['pthp_eer_coefficient_2']
    if (equipment_type == 'PTHP' || sub_category == 'PTHP') && !pthp_eer_coeff_1.nil? && !pthp_eer_coeff_2.nil?
      # TABLE 6.8.1D
      # EER = pthp_eer_coeff_1 - (pthp_eer_coeff_2 * Cap / 1000)
      # Note c: Cap means the rated cooling capacity of the product in Btu/h.
      # If the unit's capacity is less than 7000 Btu/h, use 7000 Btu/h in the calculation.
      # If the unit's capacity is greater than 15,000 Btu/h, use 15,000 Btu/h in the calculation.
      eer_calc_cap_btu_per_hr = capacity_btu_per_hr
      eer_calc_cap_btu_per_hr = 7000 if capacity_btu_per_hr < 7000
      eer_calc_cap_btu_per_hr = 15_000 if capacity_btu_per_hr > 15_000
      pthp_eer = pthp_eer_coeff_1 - (pthp_eer_coeff_2 * eer_calc_cap_btu_per_hr / 1000.0)
      cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(pthp_eer)
      new_comp_name = "#{coil_cooling_dx_single_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{pthp_eer.round(1)}EER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{coil_cooling_dx_single_speed.name}: #{cooling_type} #{heating_type} #{sub_category} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{pthp_eer.round(1)}")
    end

    # If PTAC, use equations if coefficients are specified
    ptac_eer_coeff_1 = ac_props['ptac_eer_coefficient_1']
    ptac_eer_coeff_2 = ac_props['ptac_eer_coefficient_2']
    if equipment_type == 'PTAC' && !ptac_eer_coeff_1.nil? && !ptac_eer_coeff_2.nil?
      # TABLE 6.8.1D
      # EER = ptac_eer_coeff_1 - (ptac_eer_coeff_2 * Cap / 1000)
      # Note c: Cap means the rated cooling capacity of the product in Btu/h.
      # If the unit's capacity is less than 7000 Btu/h, use 7000 Btu/h in the calculation.
      # If the unit's capacity is greater than 15,000 Btu/h, use 15,000 Btu/h in the calculation.
      eer_calc_cap_btu_per_hr = capacity_btu_per_hr
      eer_calc_cap_btu_per_hr = 7000 if capacity_btu_per_hr < 7000
      eer_calc_cap_btu_per_hr = 15_000 if capacity_btu_per_hr > 15_000
      ptac_eer = ptac_eer_coeff_1 - (ptac_eer_coeff_2 * eer_calc_cap_btu_per_hr / 1000.0)
      cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(ptac_eer)
      new_comp_name = "#{coil_cooling_dx_single_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{ptac_eer.round(1)}EER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{coil_cooling_dx_single_speed.name}: #{cooling_type} #{heating_type} #{sub_category} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{ptac_eer.round(1)}")
    end

    # If CRAC, use equations if coefficients are specified
    crac_minimum_scop = ac_props['minimum_scop']
    if sub_category == 'CRAC' && !crac_minimum_scop.nil?
      # TABLE 6.8.1K in 90.1-2010, TABLE 6.8.1-10 in 90.1-2019
      # cop = scop/sensible heat ratio
      if coil_cooling_dx_single_speed.ratedSensibleHeatRatio.is_initialized
        crac_sensible_heat_ratio = coil_cooling_dx_single_speed.ratedSensibleHeatRatio.get
      elsif coil_cooling_dx_single_speed.autosizedRatedSensibleHeatRatio.is_initialized
        # Though actual inlet temperature is very high (thus basically no dehumidification),
        # sensible heat ratio can't be pre-assigned as 1 because it should be the value at conditions defined in ASHRAE Standard 127 => 26.7 degC drybulb/19.4 degC wetbulb.
        crac_sensible_heat_ratio = coil_cooling_dx_single_speed.autosizedRatedSensibleHeatRatio.get
      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.CoilCoolingDXSingleSpeed', 'Failed to get autosized sensible heat ratio')
      end
      cop = crac_minimum_scop / crac_sensible_heat_ratio
      cop = cop.round(2)
      new_comp_name = "#{coil_cooling_dx_single_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{crac_minimum_scop}SCOP #{cop}COP"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{coil_cooling_dx_single_speed.name}: #{cooling_type} #{heating_type} #{sub_category} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; SCOP = #{crac_minimum_scop}")
    end

    # If specified as SEER
    unless ac_props['minimum_seasonal_energy_efficiency_ratio'].nil?
      min_seer = ac_props['minimum_seasonal_energy_efficiency_ratio']
      cop = OpenstudioStandards::HVAC.seer_to_cop_no_fan(min_seer)
      new_comp_name = "#{coil_cooling_dx_single_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_seer}SEER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{template}: #{coil_cooling_dx_single_speed.name}: #{cooling_type} #{heating_type} #{sub_category} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; SEER = #{min_seer}")
    end

    # If specified as SEER2
    # TODO: assumed to be the same as SEER for now
    unless ac_props['minimum_seasonal_energy_efficiency_ratio_2'].nil?
      min_seer = ac_props['minimum_seasonal_energy_efficiency_ratio_2']
      cop = OpenstudioStandards::HVAC.seer_to_cop_no_fan(min_seer)
      new_comp_name = "#{coil_cooling_dx_single_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_seer}SEER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{template}: #{coil_cooling_dx_single_speed.name}: #{cooling_type} #{heating_type} #{sub_category} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; SEER = #{min_seer}")
    end

    # If specified as EER
    unless ac_props['minimum_energy_efficiency_ratio'].nil?
      min_eer = ac_props['minimum_energy_efficiency_ratio']
      cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(min_eer)
      new_comp_name = "#{coil_cooling_dx_single_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_eer}EER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{template}: #{coil_cooling_dx_single_speed.name}: #{cooling_type} #{heating_type} #{sub_category} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{min_eer}")
    end

    # If specified as EER2
    # TODO: assumed to be the same as EER for now
    unless ac_props['minimum_energy_efficiency_ratio_2'].nil?
      min_eer = ac_props['minimum_energy_efficiency_ratio_2']
      cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(min_eer)
      new_comp_name = "#{coil_cooling_dx_single_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_eer}EER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{template}: #{coil_cooling_dx_single_speed.name}: #{cooling_type} #{heating_type} #{sub_category} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{min_eer}")
    end

    # If specific as IEER
    if !ac_props['minimum_integrated_energy_efficiency_ratio'].nil? && cop.nil?
      min_ieer = ac_props['minimum_integrated_energy_efficiency_ratio']
      cop = OpenstudioStandards::HVAC.ieer_to_cop_no_fan(min_ieer)
      new_comp_name = "#{coil_cooling_dx_single_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_ieer}IEER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXTwoSpeed', "For #{template}: #{coil_cooling_dx_single_speed.name}: #{cooling_type} #{heating_type} #{sub_category} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{min_eer}")
    end

    # If specified as SEER
    unless ac_props['minimum_seasonal_efficiency'].nil?
      min_seer = ac_props['minimum_seasonal_efficiency']
      cop = OpenstudioStandards::HVAC.seer_to_cop_no_fan(min_seer)
      new_comp_name = "#{coil_cooling_dx_single_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_seer}SEER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{template}: #{coil_cooling_dx_single_speed.name}: #{cooling_type} #{heating_type} #{sub_category} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; SEER = #{min_seer}")
    end

    # If specified as EER (heat pump)
    unless ac_props['minimum_full_load_efficiency'].nil?
      min_eer = ac_props['minimum_full_load_efficiency']
      cop = OpenstudioStandards::HVAC.eer_to_cop_no_fan(min_eer)
      new_comp_name = "#{coil_cooling_dx_single_speed.name} #{capacity_kbtu_per_hr.round}kBtu/hr #{min_eer}EER"
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{template}: #{coil_cooling_dx_single_speed.name}: #{cooling_type} #{heating_type} #{sub_category} Capacity = #{capacity_kbtu_per_hr.round}kBtu/hr; EER = #{min_eer}")
    end

    # Rename
    if rename
      coil_cooling_dx_single_speed.setName(new_comp_name)
    end

    return cop
  end

  # Applies the standard efficiency ratings and typical performance curves to this object.
  #
  # @param coil_cooling_dx_single_speed [OpenStudio::Model::CoilCoolingDXSingleSpeed] coil cooling dx single speed object
  # @param sql_db_vars_map [Hash] hash map
  # @return [Hash] hash of coil objects
  def coil_cooling_dx_single_speed_apply_efficiency_and_curves(coil_cooling_dx_single_speed, sql_db_vars_map)
    # Get efficiencies data depending on whether it is a unitary AC or a heat pump
    coil_efficiency_data = if OpenstudioStandards::HVAC.coil_dx_heat_pump?(coil_cooling_dx_single_speed)
                             standards_data['heat_pumps']
                           else
                             standards_data['unitary_acs']
                           end

    # Get the search criteria
    equipment_type = coil_efficiency_data[0].keys.include?('equipment_type') ? true : false
    search_criteria = coil_dx_find_search_criteria(coil_cooling_dx_single_speed, equipment_type)

    # Additional search criteria
    if coil_efficiency_data[0].keys.include?('equipment_type')
      if search_criteria.keys.include?('equipment_type')
        equipment_type = search_criteria['equipment_type']
        if ['PTAC', 'PTHP'].include?(equipment_type) && template.include?('90.1')
          search_criteria['application'] = coil_dx_packaged_terminal_application(coil_cooling_dx_single_speed)
        end
      elsif !OpenstudioStandards::HVAC.coil_dx_heat_pump?(coil_cooling_dx_single_speed)
        search_criteria['equipment_type'] = 'Air Conditioners'
      end
    end
    if coil_efficiency_data[0].keys.include?('region')
      search_criteria['region'] = nil # non-nil values are currently used for residential products
    end

    # Get the capacity
    if ['PTAC', 'PTHP'].include?(equipment_type) || ['PTAC', 'PTHP'].include?(OpenstudioStandards::HVAC.coil_dx_subcategory(coil_cooling_dx_single_speed))
      thermal_zone = OpenstudioStandards::HVAC.hvac_component_get_thermal_zone(coil_cooling_dx_single_speed)
      multiplier = thermal_zone.multiplier if !thermal_zone.nil?
    end
    capacity_w = OpenstudioStandards::HVAC.coil_cooling_dx_single_speed_get_capacity(coil_cooling_dx_single_speed, multiplier: multiplier)
    capacity_btu_per_hr = OpenStudio.convert(capacity_w, 'W', 'Btu/hr').get
    capacity_kbtu_per_hr = OpenStudio.convert(capacity_w, 'W', 'kBtu/hr').get

    # Lookup efficiency
    ac_props = model_find_object(coil_efficiency_data, search_criteria, capacity_btu_per_hr, Date.today)

    # Check to make sure properties were found
    if ac_props.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{coil_cooling_dx_single_speed.name}, cannot find efficiency info using #{search_criteria} and capacity #{capacity_btu_per_hr} btu/hr, cannot apply efficiency standard.")
      return sql_db_vars_map
    end

    equipment_type_field = search_criteria['equipment_type']
    # Make the COOL-CAP-FT curve
    cool_cap_ft = nil
    if ac_props['cool_cap_ft']
      cool_cap_ft = model_add_curve(coil_cooling_dx_single_speed.model, ac_props['cool_cap_ft'])
    else
      cool_cap_ft_curve_name = coil_dx_cap_ft(coil_cooling_dx_single_speed, equipment_type_field)
      cool_cap_ft = model_add_curve(coil_cooling_dx_single_speed.model, cool_cap_ft_curve_name)
    end
    if cool_cap_ft
      coil_cooling_dx_single_speed.setTotalCoolingCapacityFunctionOfTemperatureCurve(cool_cap_ft)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{coil_cooling_dx_single_speed.name}, cannot find cool_cap_ft curve, will not be set.")
    end

    # Make the COOL-CAP-FFLOW curve
    cool_cap_fflow = nil
    if ac_props['cool_cap_fflow']
      cool_cap_fflow = model_add_curve(coil_cooling_dx_single_speed.model, ac_props['cool_cap_fflow'])
    else
      cool_cap_fflow_curve_name = coil_dx_cap_fflow(coil_cooling_dx_single_speed, equipment_type_field)
      cool_cap_fflow = model_add_curve(coil_cooling_dx_single_speed.model, cool_cap_fflow_curve_name)
    end
    if cool_cap_fflow
      coil_cooling_dx_single_speed.setTotalCoolingCapacityFunctionOfFlowFractionCurve(cool_cap_fflow)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{coil_cooling_dx_single_speed.name}, cannot find cool_cap_fflow curve, will not be set.")
    end

    # Make the COOL-EIR-FT curve
    cool_eir_ft = nil
    if ac_props['cool_eir_ft']
      cool_eir_ft = model_add_curve(coil_cooling_dx_single_speed.model, ac_props['cool_eir_ft'])
    else
      cool_eir_ft_curve_name = coil_dx_eir_ft(coil_cooling_dx_single_speed, equipment_type_field)
      cool_eir_ft = model_add_curve(coil_cooling_dx_single_speed.model, cool_eir_ft_curve_name)
    end
    if cool_eir_ft
      coil_cooling_dx_single_speed.setEnergyInputRatioFunctionOfTemperatureCurve(cool_eir_ft)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{coil_cooling_dx_single_speed.name}, cannot find cool_eir_ft curve, will not be set.")
    end

    # Make the COOL-EIR-FFLOW curve
    cool_eir_fflow = nil
    if ac_props['cool_eir_fflow']
      cool_eir_fflow = model_add_curve(coil_cooling_dx_single_speed.model, ac_props['cool_eir_fflow'])
    else
      cool_eir_fflow_curve_name = coil_dx_eir_fflow(coil_cooling_dx_single_speed, equipment_type_field)
      cool_eir_fflow = model_add_curve(coil_cooling_dx_single_speed.model, cool_eir_fflow_curve_name)
    end
    if cool_eir_fflow
      coil_cooling_dx_single_speed.setEnergyInputRatioFunctionOfFlowFractionCurve(cool_eir_fflow)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{coil_cooling_dx_single_speed.name}, cannot find cool_eir_fflow curve, will not be set.")
    end

    # Make the COOL-PLF-FPLR curve
    cool_plf_fplr = nil
    if ac_props['cool_plf_fplr']
      cool_plf_fplr = model_add_curve(coil_cooling_dx_single_speed.model, ac_props['cool_plf_fplr'])
    else
      cool_plf_fplr_curve_name = coil_dx_plf_fplr(coil_cooling_dx_single_speed, equipment_type_field)
      cool_plf_fplr = model_add_curve(coil_cooling_dx_single_speed.model, cool_plf_fplr_curve_name)
    end
    if cool_plf_fplr
      coil_cooling_dx_single_speed.setPartLoadFractionCorrelationCurve(cool_plf_fplr)
    else
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{coil_cooling_dx_single_speed.name}, cannot find cool_plf_fplr curve, will not be set.")
    end

    # Keep the rated sensible heat ratio where EnergyPlus can solve the coil bypass factor.
    # Before the rename below: the sized flow and ratio are looked up by the coil's name in
    # the sizing run's results.
    coil_cooling_dx_single_speed_apply_rated_shr_cap(coil_cooling_dx_single_speed, capacity_w: multiplier.nil? ? capacity_w : capacity_w / multiplier)

    # Preserve the original name
    orig_name = coil_cooling_dx_single_speed.name.to_s

    # Find the minimum COP and rename with efficiency rating
    cop = coil_cooling_dx_single_speed_standard_minimum_cop(coil_cooling_dx_single_speed, true, equipment_type)

    # Map the original name to the new name
    sql_db_vars_map[coil_cooling_dx_single_speed.name.to_s] = orig_name

    # Set the efficiency values
    unless cop.nil?
      coil_cooling_dx_single_speed.setRatedCOP(OpenStudio::OptionalDouble.new(cop))
    end

    return sql_db_vars_map
  end

  # EnergyPlus rated inlet air for DX cooling coils: 26.67 C dry bulb, 19.44 C wet bulb.
  DX_RATED_INLET_AIR_TEMP_C = 26.6667
  DX_RATED_INLET_AIR_HUM_RAT = 0.0111847
  DX_STANDARD_PRESSURE_PA = 101_325.0

  # Rated coil bypass factor of a single speed DX cooling coil, as EnergyPlus computes it
  # from the rated capacity, air flow and sensible heat ratio (DXCoils::CalcCBF).
  #
  # The outlet air state at rated conditions follows from the capacity and the sensible heat
  # ratio; the apparatus dew point is where the line from the inlet through the outlet meets
  # the saturation curve; the bypass factor is the outlet's position on that line. A rated
  # outlet at or beyond saturation gives a zero or negative bypass factor, which EnergyPlus
  # treats as fatal.
  #
  # @param capacity_w [Double] gross rated total cooling capacity in W
  # @param flow_m3_per_s [Double] rated air flow rate in m3/s
  # @param shr [Double] rated sensible heat ratio
  # @return [Double, nil] the bypass factor, nil if the outlet state cannot be reached
  def coil_cooling_dx_single_speed_rated_bypass_factor(capacity_w, flow_m3_per_s, shr)
    return nil unless capacity_w.to_f > 0.0 && flow_m3_per_s.to_f > 0.0 && shr.to_f > 0.0

    enthalpy = ->(t, w) { (1.00484e3 * t) + (w * (2.50094e6 + (1.85895e3 * t))) }
    hum_rat_from_enthalpy = ->(t, h) { (h - (1.00484e3 * t)) / (2.50094e6 + (1.85895e3 * t)) }
    saturation_hum_rat = lambda do |t_c|
      t = t_c + 273.15 # Hyland-Wexler saturation pressure over water
      p_ws = Math.exp((-5800.2206 / t) + 1.3914993 - (0.048640239 * t) + (0.41764768e-4 * t**2) - (0.14452093e-7 * t**3) + (6.5459673 * Math.log(t)))
      0.621945 * p_ws / (DX_STANDARD_PRESSURE_PA - p_ws)
    end

    # the outlet state as EnergyPlus defines it: the latent share of the enthalpy drop is
    # taken at the inlet temperature to give the outlet humidity, then the outlet
    # temperature follows from the outlet enthalpy and humidity
    t_in = DX_RATED_INLET_AIR_TEMP_C
    w_in = DX_RATED_INLET_AIR_HUM_RAT
    h_in = enthalpy.call(t_in, w_in)
    rho = DX_STANDARD_PRESSURE_PA / (287.0 * (t_in + 273.15) * (1.0 + (1.6078 * w_in)))
    delta_h = capacity_w / (flow_m3_per_s * rho)
    w_out = hum_rat_from_enthalpy.call(t_in, h_in - ((1.0 - shr) * delta_h))
    h_out = h_in - delta_h
    t_out = (h_out - (w_out * 2.50094e6)) / (1.00484e3 + (1.85895e3 * w_out))
    return nil if t_out <= -20.0 || t_out >= t_in || w_out <= 0.0
    return 0.0 if w_out >= saturation_hum_rat.call(t_out) # outlet at or past saturation

    # apparatus dew point: bisection on the line through inlet and outlet, below the outlet
    slope = (w_in - w_out) / (t_in - t_out)
    on_line = ->(t) { w_out - (slope * (t_out - t)) }
    lo = -20.0
    hi = t_out
    return nil unless (saturation_hum_rat.call(lo) - on_line.call(lo)).negative?

    40.times do
      mid = 0.5 * (lo + hi)
      (saturation_hum_rat.call(mid) - on_line.call(mid)).negative? ? lo = mid : hi = mid
    end
    t_adp = 0.5 * (lo + hi)
    h_adp = enthalpy.call(t_adp, saturation_hum_rat.call(t_adp))
    (h_out - h_adp) / (h_in - h_adp)
  end

  # The largest rated sensible heat ratio, at or below the one given, whose rated bypass
  # factor clears a floor.
  #
  # EnergyPlus autosizes the ratio from a correlation on air flow per unit capacity
  # (0.431 + 6086 x m3/s per W), then walks it up in 0.001 steps until the apparatus dew
  # point is consistent (DXCoils::ValidateADP). For a small coil on a zone with little
  # cooling load that walk ends with the rated outlet air on the saturation curve: a 7 kBtu/h
  # storage-room coil in the 2026-09 100k run came out at 0.796 with 5.25e-5 m3/s per W,
  # a hair under saturation, and the simulation's own bypass factor iteration then came out
  # slightly negative, which is fatal. Stepping the ratio down moves the outlet off the
  # curve; the loads and flows drift a few percent between the sizing runs that follow, so
  # the floor leaves a margin rather than stopping at zero. Typical coils sit at 0.1 to 0.2.
  #
  # @param capacity_w [Double] gross rated total cooling capacity in W
  # @param flow_m3_per_s [Double] rated air flow rate in m3/s
  # @param shr [Double] rated sensible heat ratio to cap
  # @param min_bypass_factor [Double] smallest acceptable rated bypass factor
  # @param step [Double] amount the ratio is lowered per try
  # @param floor [Double] lowest ratio returned
  # @return [Double] the ratio, unchanged if it already clears the floor
  def coil_cooling_dx_single_speed_feasible_rated_shr(capacity_w, flow_m3_per_s, shr, min_bypass_factor: 0.1, step: 0.005, floor: 0.5)
    candidate = shr
    while candidate > floor
      cbf = coil_cooling_dx_single_speed_rated_bypass_factor(capacity_w, flow_m3_per_s, candidate)
      return candidate if cbf.nil? || cbf >= min_bypass_factor

      candidate = (candidate - step).round(6)
    end
    floor
  end

  # Cap a coil's rated sensible heat ratio where its sized capacity and air flow leave
  # EnergyPlus no room to solve the bypass factor, see
  # {#coil_cooling_dx_single_speed_feasible_rated_shr}. Needs sized values, so it does
  # nothing before a sizing run; a ratio that already clears the floor is left autosized.
  #
  # @param coil_cooling_dx_single_speed [OpenStudio::Model::CoilCoolingDXSingleSpeed] coil cooling dx single speed object
  # @param capacity_w [Double, nil] the coil's gross rated total cooling capacity in W, looked up when nil
  # @return [Double, nil] the ratio set, nil if the coil was left alone
  def coil_cooling_dx_single_speed_apply_rated_shr_cap(coil_cooling_dx_single_speed, capacity_w: nil)
    coil = coil_cooling_dx_single_speed
    capacity_w = OpenstudioStandards::HVAC.coil_cooling_dx_single_speed_get_capacity(coil) if capacity_w.nil?
    flow = coil.ratedAirFlowRate.is_initialized ? coil.ratedAirFlowRate.get : coil.autosizedRatedAirFlowRate
    shr = coil.ratedSensibleHeatRatio.is_initialized ? coil.ratedSensibleHeatRatio.get : coil.autosizedRatedSensibleHeatRatio
    flow = flow.get if flow.respond_to?(:is_initialized) && flow.is_initialized
    shr = shr.get if shr.respond_to?(:is_initialized) && shr.is_initialized
    return nil unless capacity_w.to_f > 0.0 && flow.is_a?(Numeric) && shr.is_a?(Numeric)

    capped = coil_cooling_dx_single_speed_feasible_rated_shr(capacity_w, flow, shr)
    return nil if capped >= shr

    coil.setRatedSensibleHeatRatio(capped)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.CoilCoolingDXSingleSpeed', "For #{coil.name}, the rated sensible heat ratio #{shr.round(3)} at #{capacity_w.round} W and #{flow.round(4)} m3/s puts the rated outlet air at saturation; set to #{capped} so EnergyPlus can solve the coil bypass factor.")
    capped
  end
end
