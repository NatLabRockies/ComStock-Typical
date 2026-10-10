class Standard
  # @!group HVAC compatibility
  #
  # The HVAC builders and the fan and air-loop queries used to be instance methods on Standard.
  # They are module functions on OpenstudioStandards::HVAC now, and ComStock's measures still
  # call these few by their old receiver. Each delegator below is kept for one release cycle so
  # that ComStock can move its call sites on its own schedule; new code calls the module.

  # @deprecated Use OpenstudioStandards::HVAC.model_add_hvac_system
  def model_add_hvac_system(model, system_type, main_heat_fuel, zone_heat_fuel, cool_fuel, zones, **options)
    OpenstudioStandards::HVAC.model_add_hvac_system(model, system_type, main_heat_fuel, zone_heat_fuel, cool_fuel, zones, **options)
  end

  # @deprecated Use OpenstudioStandards::HVAC.model_add_psz_ac
  def model_add_psz_ac(model, thermal_zones, **options)
    OpenstudioStandards::HVAC.model_add_psz_ac(model, thermal_zones, **options)
  end

  # @deprecated Use OpenstudioStandards::HVAC.model_add_ideal_air_loads
  def model_add_ideal_air_loads(model, thermal_zones, **options)
    OpenstudioStandards::HVAC.model_add_ideal_air_loads(model, thermal_zones, **options)
  end

  # @deprecated Use OpenstudioStandards::HVAC.fan_brake_horsepower
  def fan_brake_horsepower(fan)
    OpenstudioStandards::HVAC.fan_brake_horsepower(fan)
  end

  # @deprecated Use OpenstudioStandards::HVAC.fan_motor_horsepower
  def fan_motor_horsepower(fan)
    OpenstudioStandards::HVAC.fan_motor_horsepower(fan)
  end

  # @deprecated Use OpenstudioStandards::HVAC.fan_change_motor_efficiency
  def fan_change_motor_efficiency(fan, motor_eff)
    OpenstudioStandards::HVAC.fan_change_motor_efficiency(fan, motor_eff)
  end
end
