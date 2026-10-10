# A variety of fan calculation methods that are the same regardless of fan type.
# These methods are available to FanConstantVolume, FanOnOff, FanVariableVolume, and FanZoneExhaust
module Fan
  # @!group Fan

  # Applies the minimum motor efficiency for this fan based on the motor's brake horsepower.
  #
  # @param fan [OpenStudio::Model::StraightComponent] fan object, allowable types:
  #   FanConstantVolume, FanOnOff, FanVariableVolume, and FanZoneExhaust
  # @param allowed_bhp [Double] allowable brake horsepower
  # @return [Boolean] returns true if successful, false if not
  def fan_apply_standard_minimum_motor_efficiency(fan, allowed_bhp)
    # Find the motor efficiency
    motor_eff, nominal_hp = fan_standard_minimum_motor_efficiency_and_size(fan, allowed_bhp)

    # Change the motor efficiency
    # but preserve the existing fan impeller
    # efficiency.
    OpenstudioStandards::HVAC.fan_change_motor_efficiency(fan, motor_eff)

    # Calculate the total motor HP
    motor_hp = OpenstudioStandards::HVAC.fan_motor_horsepower(fan)

    # Exception for small fans, including
    # zone exhaust, fan coil, and fan powered terminals.
    # In this case, 0.5 HP is used for the lookup.
    if OpenstudioStandards::HVAC.fan_small_fan?(fan)
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Fan', "For #{fan.name}: motor eff = #{(motor_eff * 100).round(2)}%; assumed to represent several less than 1 HP motors.")
    else
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Fan', "For #{fan.name}: motor nameplate = #{nominal_hp}HP, motor eff = #{(motor_eff * 100).round(2)}%.")
    end

    return true
  end

  # Adjust the fan pressure rise to hit the target fan power (W).
  # Keep the fan impeller and motor efficiencies static.
  #
  # @param fan [OpenStudio::Model::StraightComponent] fan object, allowable types:
  #   FanConstantVolume, FanOnOff, FanVariableVolume, and FanZoneExhaust
  # @param target_fan_power [Double] the target fan power in watts
  # @return [Boolean] returns true if successful, false if not
  def fan_adjust_pressure_rise_to_meet_fan_power(fan, target_fan_power)
    # Get design supply air flow rate (whether autosized or hard-sized)
    dsn_air_flow_m3_per_s = 0
    dsn_air_flow_m3_per_s = if fan.maximumFlowRate.is_initialized
                              fan.maximumFlowRate.get
                            elsif fan.autosizedMaximumFlowRate.is_initialized
                              fan.autosizedMaximumFlowRate.get
                            end

    # Get the current fan power
    current_fan_power_w = OpenstudioStandards::HVAC.fan_fanpower(fan)

    # Get the current pressure rise (Pa)
    pressure_rise_pa = fan.pressureRise

    # Get the total fan efficiency
    fan_total_eff = fan.fanEfficiency

    # Calculate the new fan pressure rise (Pa)
    new_pressure_rise_pa = target_fan_power * fan_total_eff / dsn_air_flow_m3_per_s
    new_pressure_rise_in_h2o = OpenStudio.convert(new_pressure_rise_pa, 'Pa', 'inH_{2}O').get

    # Set the new pressure rise
    fan.setPressureRise(new_pressure_rise_pa)

    # Calculate the new power
    new_power_w = OpenstudioStandards::HVAC.fan_fanpower(fan)

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Fan', "For #{fan.name}: pressure rise = #{new_pressure_rise_in_h2o.round(1)} in w.c., power = #{OpenstudioStandards::HVAC.fan_motor_horsepower(fan).round(2)}HP.")

    return true
  end

  # Determines the baseline fan impeller efficiency based on the specified fan type.
  #
  # @param fan [OpenStudio::Model::StraightComponent] fan object, allowable types:
  #   FanConstantVolume, FanOnOff, FanVariableVolume, and FanZoneExhaust
  # @return [Double] impeller efficiency (0.0 to 1.0)
  # @todo Add fan type to data model and modify this method
  def fan_baseline_impeller_efficiency(fan)
    # Assume that the fan efficiency is 65% for normal fans
    # and 55% for small fans (like exhaust fans).
    # @todo add fan type to fan data model
    # and infer impeller efficiency from that?
    # or do we always assume a certain type of
    # fan impeller for the baseline system?
    # @todo check COMNET and T24 ACM and PNNL 90.1 doc
    fan_impeller_eff = 0.65

    if OpenstudioStandards::HVAC.fan_small_fan?(fan)
      fan_impeller_eff = 0.55
    end

    return fan_impeller_eff
  end

  # Determines the minimum fan motor efficiency and nominal size for a given motor bhp.
  # This should be the total brake horsepower with any desired safety factor already included.
  #
  # The lookup is a single step: find the row in the motors table whose
  # [minimum_capacity, maximum_capacity] range contains the brake horsepower, and return that
  # row's efficiency. The row's maximum_capacity is reported as the nominal motor size, rounded
  # to a whole number at or above 2 HP.
  # For example, for 90.1-2010 a bhp of 6.3 falls in the 5.001-7.500 row, giving an efficiency
  # of 91.7% (4-pole, enclosed) and a reported nominal size of 8 HP (7.5 rounded).
  # This method assumes 4-pole, 1800rpm totally-enclosed fan-cooled motors.
  #
  # Note that 90.1 and DEER motors tables carry date-effective rows, and the lookup passes
  # Date.today, so a single bin can resolve to different efficiencies depending on when the
  # code runs -- the 90.1-2010 example above is 89.5% before 2010-12-19 and 91.7% after. The
  # DOE Ref tables have no date fields and always resolve to a single row.
  #
  # Because the lookup is single step, each motors table row must carry the efficiency of a
  # motor actually serving that brake-horsepower range. An earlier version of this method took
  # a second step, re-looking-up at maximum_capacity + 0.01 to land one row higher, and the
  # DOE Ref tables were authored around that behaviour -- their rows were offset by one bin and
  # a 0.29 "PSC motors below 1 HP" row sat at the bottom where the second step always skipped
  # it. When the second step was removed upstream (openstudio-standards commit fddbdc9,
  # PR #1716), that row became reachable and every sub-1-HP DOE Ref fan silently dropped from
  # 0.825 to 0.29 motor efficiency. The DOE Ref tables have since been corrected to match this
  # single-step contract. Keep table and lookup consistent: do not reintroduce a second step,
  # and do not insert a row that only makes sense if one exists.
  #
  # @param fan [OpenStudio::Model::StraightComponent] fan object, allowable types:
  #   FanConstantVolume, FanOnOff, FanVariableVolume, and FanZoneExhaust
  # @param motor_bhp [Double] motor brake horsepower (hp)
  # @return [Array<Double>] minimum motor efficiency (0.0 to 1.0), nominal horsepower
  def fan_standard_minimum_motor_efficiency_and_size(fan, motor_bhp)
    fan_motor_eff = 0.85
    # Fallback nominal size, returned only when the table lookup below fails.
    # Assumes that the fan brake horsepower is 90% of the fan nameplate rated motor power,
    # per the method used in PNNL prototype buildings.
    # Source: Thornton et al. (2011), Achieving the 30% Goal: Energy and Cost Savings Analysis of ASHRAE Standard 90.1-2010, Section 4.5.4
    nominal_hp = motor_bhp * 1.1

    # Don't attempt to look up motor efficiency
    # for zero-hp fans, which may occur when there is no
    # airflow required for a particular system, typically
    # heated-only spaces with high internal gains
    # and no OA requirements such as elevator shafts.
    return [fan_motor_eff, 0] if motor_bhp < 0.0001

    # Lookup the minimum motor efficiency
    motors = standards_data['motors']

    # Assuming all fan motors are 4-pole ODP
    search_criteria = {
      'template' => template,
      'number_of_poles' => 4.0,
      'type' => 'Enclosed'
    }

    # Exception for small fans, including
    # zone exhaust, fan coil, and fan powered terminals.
    # In this case, use the 0.5 HP for the lookup.
    if OpenstudioStandards::HVAC.fan_small_fan?(fan)
      nominal_hp = 0.5

      # Get the efficiency based on the nominal horsepower
      motor_type = motor_type(nominal_hp)
      motor_properties = motor_fractional_hp_efficiencies(nominal_hp, motor_type = motor_type)

      if motor_properties.nil?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Fan', "For #{fan.name}, could not find nominal motor properties using search criteria: #{search_criteria}, motor_hp = #{nominal_hp} hp.")
        return [fan_motor_eff, nominal_hp]
      end
    else
      # Use the efficiency largest motor efficiency when BHP is greater than the largest size for which a requirement is provided
      data = model_find_objects(motors, search_criteria)
      maximum_capacity = model_find_maximum_value(data, 'maximum_capacity')
      if motor_bhp > maximum_capacity
        motor_bhp = maximum_capacity
      end

      motor_properties = model_find_object(motors, search_criteria, capacity = nil, date = Date.today, area = nil, num_floors = nil, fan_motor_bhp = motor_bhp)
      if motor_properties.nil?
        # Retry without the date
        motor_properties = model_find_object(motors, search_criteria, capacity = nil, date = nil, area = nil, num_floors = nil, fan_motor_bhp = motor_bhp)
        if motor_properties.nil?
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Fan', "For #{fan.name}, could not find motor properties using search criteria: #{search_criteria}, motor_bhp = #{motor_bhp} hp.")
          return [fan_motor_eff, nominal_hp]
        end
      end
    end

    nominal_hp = motor_properties['maximum_capacity'].to_f.round(1)
    # Round to nearest whole HP for niceness
    if nominal_hp >= 2
      nominal_hp = nominal_hp.round
    end

    fan_motor_eff = motor_properties['nominal_full_load_efficiency']

    return [fan_motor_eff, nominal_hp]
  end
end
