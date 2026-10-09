class DOERefPre1980 < ASHRAE901
  # @!group AirLoopHVAC

  # Apply multizone vav outdoor air method and adjust multizone VAV damper positions.
  # Currently doesn't do anything for the DOE prototype buildings.
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # return [Boolean] returns true if successful, false if not
  # @todo enable damper position adjustment for legacy IDFS
  def air_loop_hvac_apply_multizone_vav_outdoor_air_sizing(air_loop_hvac)
    OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.AirLoopHVAC', 'Damper positions not modified for DOE Ref Pre-1980 or DOE Ref 1980-2004 vintages.')
    return true
  end

  # Determine if static pressure reset is required for this system.
  # Not required by DOE Pre-1980.
  #
  # @todo Instead of requiring the input of whether a system
  #   has DDC control of VAV terminals or not, determine this
  #   from the system itself.  This may require additional information
  #   be added to the OpenStudio data model.
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @param has_ddc [Boolean] whether or not the system has DDC control over VAV terminals.
  # return [Boolean] returns true if static pressure reset is required, false if not
  def air_loop_hvac_static_pressure_reset_required?(air_loop_hvac, has_ddc)
    sp_reset_required = false
    return sp_reset_required
  end

  # Determines if optimum start control is required.
  # Not required by DOE Pre-1980.
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @return [Boolean] returns true if required, false if not
  def air_loop_hvac_optimum_start_required?(air_loop_hvac)
    opt_start_required = false
    return opt_start_required
  end

  # Determine whether the VAV damper control is single maximum or dual maximum control.
  # Single Maximum for DOE Ref Pre-1980.
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @return [String] the damper control type: Single Maximum, Dual Maximum
  def air_loop_hvac_vav_damper_action(air_loop_hvac)
    damper_action = 'Single Maximum'
    return damper_action
  end

  # Determine minimum ventilation efficiency for zones.
  # For DOE Ref Pre-1980, assume that VAV system designers did not
  # care about decreasing system OA flow rates and therefore did not
  # adjust minimum damper positions to achieve any specific
  # ventilation efficiency.
  def air_loop_hvac_minimum_zone_ventilation_efficiency(air_loop_hvac)
    min_ventilation_efficiency = 0

    return min_ventilation_efficiency
  end

  # Determine the minimum outdoor air control for multizone VAV systems.
  # For DOE Ref Pre-1980, the minimum outdoor air damper is set to its design position at design supply
  # flow and left there, the common control before outdoor airflow measurement and damper reset,
  # so outdoor air falls with the supply fan.
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @return [String] 'ProportionalMinimum'
  def air_loop_hvac_minimum_outdoor_air_limit_type(air_loop_hvac)
    return 'ProportionalMinimum'
  end

  # Determine whether a VAV terminal's minimum is raised to cover its zone's design outdoor air.
  # For DOE Ref Pre-1980, terminals keep their 30% minimum where ventilation is occupant driven, which a
  # fixed minimum damper serves as a fraction of supply flow. Zones whose outdoor air is set by
  # air changes or by floor area alone (health care rooms, laboratories) keep the raise, since that
  # air is required whatever the load.
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @param zone [OpenStudio::Model::ThermalZone] the zone the terminal serves
  # @return [Boolean] true if any space in the zone has air-change or area-only outdoor air
  def air_loop_hvac_vav_terminal_minimum_covers_zone_outdoor_air?(air_loop_hvac, zone)
    zone.spaces.any? do |space|
      dsoa = space.designSpecificationOutdoorAir
      dsoa = space.spaceType.get.designSpecificationOutdoorAir if dsoa.empty? && space.spaceType.is_initialized
      next false if dsoa.empty?

      dsoa = dsoa.get
      dsoa.outdoorAirFlowAirChangesperHour > 0.0 ||
        (dsoa.outdoorAirFlowperPerson <= 0.0 && dsoa.outdoorAirFlowperFloorArea > 0.0)
    end
  end
end
