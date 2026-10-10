module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group AirLoop:Controls
    # Methods to set Air Loop HVAC controls

    # Returns standard air loop design sizing temperatures
    #
    # @return [Hash] Hash of design sizing temperature lookups
    def self.standard_air_loop_design_sizing_temperatures
      dsgn_temps = {}
      dsgn_temps['prehtg_dsgn_sup_air_temp_f'] = 45.0
      dsgn_temps['preclg_dsgn_sup_air_temp_f'] = 55.0
      dsgn_temps['htg_dsgn_sup_air_temp_f'] = 55.0
      dsgn_temps['clg_dsgn_sup_air_temp_f'] = 55.0
      dsgn_temps['zn_htg_dsgn_sup_air_temp_f'] = 104.0
      dsgn_temps['zn_clg_dsgn_sup_air_temp_f'] = 55.0
      dsgn_temps['prehtg_dsgn_sup_air_temp_c'] = OpenStudio.convert(dsgn_temps['prehtg_dsgn_sup_air_temp_f'], 'F', 'C').get
      dsgn_temps['preclg_dsgn_sup_air_temp_c'] = OpenStudio.convert(dsgn_temps['preclg_dsgn_sup_air_temp_f'], 'F', 'C').get
      dsgn_temps['htg_dsgn_sup_air_temp_c'] = OpenStudio.convert(dsgn_temps['htg_dsgn_sup_air_temp_f'], 'F', 'C').get
      dsgn_temps['clg_dsgn_sup_air_temp_c'] = OpenStudio.convert(dsgn_temps['clg_dsgn_sup_air_temp_f'], 'F', 'C').get
      dsgn_temps['zn_htg_dsgn_sup_air_temp_c'] = OpenStudio.convert(dsgn_temps['zn_htg_dsgn_sup_air_temp_f'], 'F', 'C').get
      dsgn_temps['zn_clg_dsgn_sup_air_temp_c'] = OpenStudio.convert(dsgn_temps['zn_clg_dsgn_sup_air_temp_f'], 'F', 'C').get
      return dsgn_temps
    end

    # Sets the air loop system sizing parameters
    #
    # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
    # @param design_temperatures [Hash] a hash of design temperature lookups from standard_air_loop_design_sizing_temperatures
    # @param type_of_load_sizing [String] type of load to size on
    # @param minimum_system_airflow_ratio [Double, Symbol, nil] the central heating maximum system air flow
    #   ratio, between 0 and 1: the fraction of the cooling design flow the central heating coil is sized
    #   to heat. A number pins it; :autosize or nil lets EnergyPlus derive it from the sum of the zones'
    #   heating design flows over the cooling design flow, which is the airflow VAV terminals actually
    #   pass in heating once their minimum outdoor air and reverse action are counted. A pinned 0.3
    #   under-sized a hospital's central coil by a third in a validation run, since its laboratory and
    #   patient zones carry minimum outdoor air well above 30% of their peaks.
    # @param sizing_option [String] sizing option. Options are 'Coincident' and 'NonCoincident'
    # @return [OpenStudio::Model::SizingSystem] sizing system object
    def self.set_air_loop_system_sizing(air_loop_hvac,
                                        design_temperatures,
                                        type_of_load_sizing: 'Sensible',
                                        minimum_system_airflow_ratio: 0.3,
                                        sizing_option: 'Coincident')
      # adjust sizing system defaults
      sizing_system = air_loop_hvac.sizingSystem
      sizing_system.setTypeofLoadtoSizeOn(type_of_load_sizing)
      sizing_system.autosizeDesignOutdoorAirFlowRate
      sizing_system.setPreheatDesignTemperature(design_temperatures['prehtg_dsgn_sup_air_temp_c'])
      sizing_system.setPrecoolDesignTemperature(design_temperatures['preclg_dsgn_sup_air_temp_c'])
      sizing_system.setCentralCoolingDesignSupplyAirTemperature(design_temperatures['clg_dsgn_sup_air_temp_c'])
      sizing_system.setCentralHeatingDesignSupplyAirTemperature(design_temperatures['htg_dsgn_sup_air_temp_c'])
      sizing_system.setPreheatDesignHumidityRatio(0.008)
      sizing_system.setPrecoolDesignHumidityRatio(0.008)
      sizing_system.setCentralCoolingDesignSupplyAirHumidityRatio(0.0085)
      sizing_system.setCentralHeatingDesignSupplyAirHumidityRatio(0.0080)
      set_air_loop_system_sizing_heating_airflow_ratio(sizing_system, minimum_system_airflow_ratio)
      sizing_system.setSizingOption(sizing_option)
      sizing_system.setAllOutdoorAirinCooling(false)
      sizing_system.setAllOutdoorAirinHeating(false)
      sizing_system.setSystemOutdoorAirMethod('ZoneSum')
      sizing_system.setCoolingDesignAirFlowMethod('DesignDay')
      sizing_system.setHeatingDesignAirFlowMethod('DesignDay')

      return sizing_system
    end

    # Set or autosize the central heating maximum system air flow ratio on a Sizing:System.
    #
    # @param sizing_system [OpenStudio::Model::SizingSystem] sizing system object
    # @param minimum_system_airflow_ratio [Double, Symbol, nil] a number pins the ratio; :autosize or nil
    #   lets EnergyPlus derive it from the zones' heating design flows
    # @return [Boolean] returns true if successful, false if not
    def self.set_air_loop_system_sizing_heating_airflow_ratio(sizing_system, minimum_system_airflow_ratio)
      autosize = minimum_system_airflow_ratio.nil? || minimum_system_airflow_ratio == :autosize
      if sizing_system.model.version < OpenStudio::VersionString.new('2.7.0')
        if autosize
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.HVAC', "The minimum system air flow ratio cannot be autosized before OpenStudio 2.7.0; #{sizing_system.name} keeps 0.3.")
          sizing_system.setMinimumSystemAirFlowRatio(0.3)
        else
          sizing_system.setMinimumSystemAirFlowRatio(minimum_system_airflow_ratio)
        end
      elsif autosize
        sizing_system.autosizeCentralHeatingMaximumSystemAirFlowRatio
      else
        sizing_system.setCentralHeatingMaximumSystemAirFlowRatio(minimum_system_airflow_ratio)
      end

      return true
    end

    # Size a zone's design air flow with a floor, for a zone served by a unit of its own.
    #
    # Sizing:Zone's DesignDay method takes the air flow from the design load alone, so a zone
    # with no design heating or cooling load gets none, and a per-zone unit (a residential
    # furnace and central AC, a central air source heat pump) then has no air flow to size its
    # fan: EnergyPlus stops with "Unable to determine fan air flow rate". A 2026-09 small hotel
    # did this with an interior, ground-contact restroom whose lighting gain went to the slab
    # and its neighbours. The cooling method DesignDayWithLimit takes the larger of the
    # design-load flow and the zone's cooling minimum air flow per floor area (the Sizing:Zone
    # default, 0.000762 m3/s-m2, that is 0.15 cfm/ft2, unless set), so the flow is never zero;
    # the unit's single supply flow follows it. Only the method changes; the minimum stays
    # whatever the zone carries. The heating method is left at DesignDay, as in the VAV
    # builders: its "maximum" fields cap the heating flow rather than floor it.
    #
    # @param thermal_zone [OpenStudio::Model::ThermalZone] OpenStudio ThermalZone object
    # @return [OpenStudio::Model::SizingZone] the zone's sizing object
    def self.thermal_zone_apply_residential_air_flow_floor(thermal_zone)
      sizing_zone = thermal_zone.sizingZone
      sizing_zone.setCoolingDesignAirFlowMethod('DesignDayWithLimit')
      sizing_zone
    end
  end
end
