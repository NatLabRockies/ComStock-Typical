class Standard
  # @!group AirTerminalSingleDuctParallelPIUReheat

  # Return the fan on flow fraction for a parallel PIU terminal.
  #
  # When returning nil, the fan on flow fraction will be set to
  # be autosize in the EnergyPlus model; OpenStudio assumes that
  # the default is "autosize". When autosized, this input is set
  # to be the same as the minimum primary air flow fraction which
  # means that the secondary fan will be on when the primary air
  # flow is at the minimum flow fraction.
  #
  # @return [Double] returns nil or a float representing the fraction
  def air_terminal_single_duct_parallel_piu_reheat_fan_on_flow_fraction
    return nil
  end

  # Specifies the minimum primary air flow fraction for PFB boxes.
  #
  # @param air_terminal_single_duct_parallel_piu_reheat [OpenStudio::Model::AirTerminalSingleDuctParallelPIUReheat] air terminal object
  # @return [Double] minimum primaru air flow fraction
  def air_terminal_single_duct_parallel_reheat_piu_minimum_primary_airflow_fraction(air_terminal_single_duct_parallel_piu_reheat)
    min_primary_airflow_fraction = 0.3
    return min_primary_airflow_fraction
  end

  # Set the minimum primary air flow fraction based on OA rate of the space and the template.
  #
  # @param air_terminal_single_duct_parallel_piu_reheat [OpenStudio::Model::AirTerminalSingleDuctParallelPIUReheat] the air terminal object
  # @param zone_min_oa [Double] the zone outdoor air flow rate, in m^3/s.
  # @return [Boolean] returns true if successful, false if not
  def air_terminal_single_duct_parallel_piu_reheat_apply_minimum_primary_airflow_fraction(air_terminal_single_duct_parallel_piu_reheat, zone_min_oa = nil)
    # Minimum primary air flow
    min_primary_airflow_frac = air_terminal_single_duct_parallel_reheat_piu_minimum_primary_airflow_fraction(air_terminal_single_duct_parallel_piu_reheat)
    air_terminal_single_duct_parallel_piu_reheat.setMinimumPrimaryAirFlowFraction(min_primary_airflow_frac)
    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.AirTerminalSingleDuctParallelPIUReheat', "For #{air_terminal_single_duct_parallel_piu_reheat.name}: set minimum primary air flow fraction to #{min_primary_airflow_frac}.")

    # Minimum OA flow rate
    # If specified, set the primary air flow fraction as
    unless zone_min_oa.nil?
      min_primary_airflow_frac = [min_primary_airflow_frac, zone_min_oa / air_terminal_single_duct_parallel_piu_reheat.autosizedMaximumPrimaryAirFlowRate.get].max
      air_terminal_single_duct_parallel_piu_reheat.setMinimumPrimaryAirFlowFraction(min_primary_airflow_frac)
    end

    return true
  end
end
