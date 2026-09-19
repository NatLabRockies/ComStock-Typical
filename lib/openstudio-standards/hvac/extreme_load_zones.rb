module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Extreme load zones
    # Zones whose internal loads are far above the rest of the building get their own systems
    # rather than a terminal on the building's main system. Data centers and computer rooms get
    # a CRAC or CRAH, matching the building's cooling source; anything else above the threshold
    # gets a packaged single-zone unit on that source.
    #
    # Why: a 100 W/ft2 data center zone on an office's packaged VAV system is sized with the
    # office zones and served at the office supply temperature. In the 2026-09 Kestrel run every
    # large office with a data center on a PVAV system either failed its sizing run outright,
    # while the zone read as heated-only, or ran with thousands of unmet cooling hours once it
    # did not. The DOE prototypes never do this: their data centers are on CRAC units when the
    # building is DX-cooled and CRAH units on the chilled water plant otherwise.

    # Standards space type name fragments, compared with spaces removed and case ignored, that
    # mark a space as a data center or computer room.
    DATA_CENTER_SPACE_TYPE_KEYWORDS = %w[datacenter computerroom serverroom itroom itcloset].freeze

    # A named data center or computer room space type must also carry at least this much
    # electric equipment to be treated as one: a school's computer lab is a classroom.
    DATA_CENTER_MIN_EQUIPMENT_W_PER_FT2 = 20.0

    # Electric equipment density above which any zone is an extreme load zone, whatever it is
    # called. Kitchens top out near 47 W/ft2 in the typical data, so 50 leaves them on the main
    # system while catching every data center density.
    EXTREME_LOAD_EQUIPMENT_W_PER_FT2 = 50.0

    # Design electric equipment power density of a zone.
    #
    # @param thermal_zone [OpenStudio::Model::ThermalZone] OpenStudio ThermalZone object
    # @return [Double] W/ft2 of floor area, 0 when the zone has no floor area
    def self.thermal_zone_electric_equipment_w_per_ft2(thermal_zone)
      return 0.0 unless thermal_zone.floorArea > 0.0

      w_per_m2 = thermal_zone.electricEquipmentPowerPerFloorArea
      return OpenStudio.convert(w_per_m2, 'W/m^2', 'W/ft^2').get
    end

    # Whether a zone holds a data center or computer room space: a space type named as one that
    # also carries data-center-class equipment.
    #
    # @param thermal_zone [OpenStudio::Model::ThermalZone] OpenStudio ThermalZone object
    # @param min_w_per_ft2 [Double] equipment density a named space must reach
    # @return [Boolean] true if the zone is a data center
    def self.thermal_zone_data_center?(thermal_zone, min_w_per_ft2: DATA_CENTER_MIN_EQUIPMENT_W_PER_FT2)
      named = thermal_zone.spaces.any? do |space|
        next false unless space.spaceType.is_initialized
        next false unless space.spaceType.get.standardsSpaceType.is_initialized

        name = space.spaceType.get.standardsSpaceType.get.downcase.gsub(%r{[\s_/-]}, '')
        DATA_CENTER_SPACE_TYPE_KEYWORDS.any? { |keyword| name.include?(keyword) }
      end
      return false unless named

      return thermal_zone_electric_equipment_w_per_ft2(thermal_zone) >= min_w_per_ft2
    end

    # Split zones into those the main system should serve and those that need their own.
    #
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] zones to classify
    # @param extreme_w_per_ft2 [Double] equipment density above which a zone is an extreme load zone
    # @return [Hash] { main: [...], data_center: [...], extreme: [...] }; a data center is not
    #   also listed as extreme
    def self.split_extreme_load_zones(thermal_zones, extreme_w_per_ft2: EXTREME_LOAD_EQUIPMENT_W_PER_FT2)
      groups = { main: [], data_center: [], extreme: [] }
      thermal_zones.each do |zone|
        if thermal_zone_data_center?(zone)
          groups[:data_center] << zone
        elsif thermal_zone_electric_equipment_w_per_ft2(zone) >= extreme_w_per_ft2
          groups[:extreme] << zone
        else
          groups[:main] << zone
        end
      end
      groups
    end

    # The cooling source a CBECS HVAC system type draws on, read from its name.
    #
    # @param hvac_system_type [String] CBECS HVAC system type, e.g. 'VAV chiller with PFP boxes'
    # @return [Hash] { chilled_water: Boolean, cool_fuel: 'Electricity' or 'DistrictCooling',
    #   chilled_water_loop_cooling_type: 'AirCooled' or 'WaterCooled' }
    def self.cbecs_hvac_cooling_source(hvac_system_type)
      name = hvac_system_type.to_s.downcase
      if name.include?('district chilled water')
        { chilled_water: true, cool_fuel: 'DistrictCooling', chilled_water_loop_cooling_type: 'WaterCooled' }
      elsif name.include?('air-cooled chiller')
        { chilled_water: true, cool_fuel: 'Electricity', chilled_water_loop_cooling_type: 'AirCooled' }
      elsif name.include?('chiller')
        { chilled_water: true, cool_fuel: 'Electricity', chilled_water_loop_cooling_type: 'WaterCooled' }
      else
        { chilled_water: false, cool_fuel: 'Electricity', chilled_water_loop_cooling_type: 'WaterCooled' }
      end
    end

    # Serve data center zones with a CRAH on the building's chilled water plant when its main
    # system has one, otherwise with a DX CRAC per zone.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param standard [Standard] a Standard object
    # @param hvac_system_type [String] the building's CBECS HVAC system type
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] data center zones
    # @return [Boolean] true if the systems were added, false if not
    def self.add_data_center_systems(model, standard, hvac_system_type, thermal_zones)
      return true if thermal_zones.empty?

      source = cbecs_hvac_cooling_source(hvac_system_type)
      names = thermal_zones.map { |zone| zone.name.to_s }.join(', ')
      if source[:chilled_water]
        chilled_water_loop = standard.model_get_or_add_chilled_water_loop(model, source[:cool_fuel],
                                                                          chilled_water_loop_cooling_type: source[:chilled_water_loop_cooling_type])
        result = standard.model_add_crah(model, thermal_zones, chilled_water_loop: chilled_water_loop)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.HVAC', "Data center zones #{names} are served by a CRAH on #{chilled_water_loop.name}, the chilled water plant of the #{hvac_system_type} system, rather than by that system.")
        return !result.is_a?(FalseClass) # the builders return model objects on success
      end

      climate_zone = OpenstudioStandards::Weather.model_get_climate_zone(model)
      if climate_zone.empty?
        climate_zone = 'ASHRAE 169-2013-4A'
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.HVAC', "The model has no climate zone; the CRAC economizer decision for #{names} assumes #{climate_zone}.")
      end
      result = standard.model_add_crac(model, thermal_zones, climate_zone)
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.HVAC', "Data center zones #{names} are served by DX CRAC units rather than by the #{hvac_system_type} system.")
      return !result.is_a?(FalseClass) # the builders return model objects on success
    end

    # Serve extreme load zones that are not data centers with a packaged single-zone unit on
    # the building's cooling source, with electric heat.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param standard [Standard] a Standard object
    # @param hvac_system_type [String] the building's CBECS HVAC system type
    # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] extreme load zones
    # @return [Boolean] true if the systems were added, false if not
    def self.add_extreme_load_zone_systems(model, standard, hvac_system_type, thermal_zones)
      return true if thermal_zones.empty?

      source = cbecs_hvac_cooling_source(hvac_system_type)
      names = thermal_zones.map { |zone| zone.name.to_s }.join(', ')
      result = standard.model_add_hvac_system(model, 'PSZ-AC', nil, 'Electricity', source[:cool_fuel], thermal_zones,
                                              chilled_water_loop_cooling_type: source[:chilled_water_loop_cooling_type])
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.HVAC', "Extreme load zones #{names} are served by their own packaged single-zone units on #{source[:cool_fuel]} cooling rather than by the #{hvac_system_type} system.")
      return !result.is_a?(FalseClass) # the builders return model objects on success
    end
  end
end
