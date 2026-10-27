module OpenstudioStandards
  # The Refrigeration module provides methods to create, modify, and get information about refrigeration
  module Refrigeration
    # @!group Information
    # Methods to get information about model refrigeration

    # Find the thermal zone that is best for adding refrigerated display cases into.
    # First, check for space types that typically have refrigeration.
    # Fall back to all zones in the model if no typical space types are found.
    # The zone is chosen from the candidates by refrigeration_preferred_zone.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @return [OpenStudio::Model::ThermalZone] returns a thermal zone if found, nil if not.
    def self.refrigeration_case_zone(model)
      # load refrigeration cases data
      cases_csv = "#{File.dirname(__FILE__)}/data/typical_refrigerated_cases.csv"
      unless File.file?(cases_csv)
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Refrigeration', "Unable to find file: #{cases_csv}")
        return nil
      end
      cases_tbl = CSV.table(cases_csv, encoding: 'ISO8859-1:utf-8')
      cases_hsh = cases_tbl.map(&:to_hash)
      tagged_names = OpenstudioStandards::Refrigeration.refrigeration_tagged_names(cases_hsh)

      # Look for one of the space types that would typically have refrigeration
      candidate_zones = model.getThermalZones.select do |zone|
        space_type = OpenstudioStandards::ThermalZone.thermal_zone_get_space_type(zone)
        next false if space_type.empty?

        space_type = space_type.get
        next false if space_type.standardsSpaceType.empty?
        next false if space_type.standardsBuildingType.empty?

        stds_spc_type = space_type.standardsSpaceType.get
        stds_bldg_type = space_type.standardsBuildingType.get
        cases_hsh.any? { |r| OpenstudioStandards::Refrigeration.refrigeration_record_applies?(r, stds_spc_type, stds_bldg_type, tagged_names: tagged_names) }
      end

      display_case_zone = OpenstudioStandards::Refrigeration.refrigeration_preferred_zone(candidate_zones)
      unless display_case_zone.nil?
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Refrigeration', "Display case zone is #{display_case_zone.name}, the preferred zone with a space type typical for display cases.")
        return display_case_zone
      end

      # If no typical space type was found, choose from all zones in the model.
      display_case_zone = OpenstudioStandards::Refrigeration.refrigeration_preferred_zone(model.getThermalZones)
      unless display_case_zone.nil?
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Refrigeration', "No space types typical for display cases were found, so the display cases will be placed in #{display_case_zone.name}, the preferred zone.")
        return display_case_zone
      end

      return display_case_zone
    end

    # Find the thermal zone that is best for adding refrigerated walkins into.
    # First, check for space types that typically have refrigeration.
    # Fall back to all zones in the model if no typical space types are found.
    # The zone is chosen from the candidates by refrigeration_preferred_zone.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @return [OpenStudio::Model::ThermalZone] returns a thermal zone if found, nil if not.
    def self.refrigeration_walkin_zone(model)
      # load refrigeration walkin data
      walkins_csv = "#{File.dirname(__FILE__)}/data/typical_refrigerated_walkins.csv"
      unless File.file?(walkins_csv)
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Refrigeration', "Unable to find file: #{walkins_csv}")
        return nil
      end
      walkins_tbl = CSV.table(walkins_csv, encoding: 'ISO8859-1:utf-8')
      walkins_hsh = walkins_tbl.map(&:to_hash)
      tagged_names = OpenstudioStandards::Refrigeration.refrigeration_tagged_names(walkins_hsh)

      # Look for one of the space types that would typically have walkins
      candidate_zones = model.getThermalZones.select do |zone|
        space_type = OpenstudioStandards::ThermalZone.thermal_zone_get_space_type(zone)
        next false if space_type.empty?

        space_type = space_type.get
        next false if space_type.standardsSpaceType.empty?
        next false if space_type.standardsBuildingType.empty?

        stds_spc_type = space_type.standardsSpaceType.get
        stds_bldg_type = space_type.standardsBuildingType.get
        walkins_hsh.any? { |r| OpenstudioStandards::Refrigeration.refrigeration_record_applies?(r, stds_spc_type, stds_bldg_type, tagged_names: tagged_names) }
      end

      walkin_zone = OpenstudioStandards::Refrigeration.refrigeration_preferred_zone(candidate_zones)
      unless walkin_zone.nil?
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Refrigeration', "Walkin zone is #{walkin_zone.name}, the preferred zone with a space type typical for walkins.")
        return walkin_zone
      end

      # If no typical space type was found,
      # choose from all zones in the model.
      walkin_zone = OpenstudioStandards::Refrigeration.refrigeration_preferred_zone(model.getThermalZones)
      unless walkin_zone.nil?
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Refrigeration', "No space types typical for walkins were found, so the walkins will be placed in #{walkin_zone.name}, the preferred zone.")
        return walkin_zone
      end

      return walkin_zone
    end

    # Choose the zone to hold refrigeration equipment from a set of candidate zones.
    # Model object order is not stable between runs, so the candidates are narrowed in a fixed order:
    # 1. Lowest zone multiplier. EnergyPlus meters refrigeration equipment once but multiplies the zone load
    #    its credits create, so equipment in a multiplied zone imposes its credits on the HVAC more than once.
    # 2. Largest floor area.
    # 3. Zone name, as a final stable tie-break.
    #
    # @param zones [Array<OpenStudio::Model::ThermalZone>] candidate thermal zones
    # @param area_tolerance [Double] tolerance for floor area comparison, in m^2
    # @return [OpenStudio::Model::ThermalZone] the preferred zone, nil if there are no candidates
    def self.refrigeration_preferred_zone(zones, area_tolerance: 0.01)
      zones = zones.to_a
      return nil if zones.empty?

      min_multiplier = zones.map(&:multiplier).min
      zones = zones.select { |zone| zone.multiplier == min_multiplier }
      if min_multiplier > 1
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Refrigeration', "Every candidate zone for refrigeration equipment has a zone multiplier of at least #{min_multiplier}. EnergyPlus will apply the refrigeration credits to the zone #{min_multiplier} times but meter the equipment once.")
      end

      max_area = zones.map(&:floorArea).max
      zones = zones.select { |zone| zone.floorArea >= max_area - area_tolerance }

      return zones.min_by(&:nameString)
    end
  end
end
