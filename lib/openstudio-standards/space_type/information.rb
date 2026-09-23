module OpenstudioStandards
  # The SpaceType module provides methods to create, modify, and get information about space types
  module SpaceType
    # @!group Information
    # Methods to identify what a space type is, in the typical (all-level) space type vocabulary,
    # whichever naming a model carries.
    #
    # A model built from a custom building spec names its space types with the all-level vocabulary
    # ('food preparation', 'corridor - hospital'). A model built from the prototype space types names
    # them with the prototype vocabulary ('Kitchen', 'PatCorridor'). Measures that classify spaces,
    # zones and air loops should use these methods rather than matching names, so they read both.

    LEVEL_1_SPACE_TYPES_PATH = File.join(__dir__, 'data', 'level_1_space_types.json')
    ALL_LEVEL_SPACE_TYPES_PATH = File.join(__dir__, 'data', 'all_level_space_types.json')
    PROTOTYPE_SPACE_TYPE_MAP_PATH = File.join(__dir__, '..', 'prototypes', 'common', 'data', 'prototype_space_type_map.json')

    # Names of the level-1 typical space types ('office', 'food preparation').
    #
    # @return [Array<String>] level-1 space type names
    def self.level_1_space_type_names
      @level_1_space_type_names ||= JSON.parse(File.read(LEVEL_1_SPACE_TYPES_PATH)).map { |row| row['space_type_name'] }.freeze
    end

    # Names of every typical space type: the level-1 names and their qualified variants
    # ('corridor - hospital', 'food preparation - primary school').
    #
    # @return [Array<String>] all-level space type names
    def self.all_level_space_type_names
      @all_level_space_type_names ||= JSON.parse(File.read(ALL_LEVEL_SPACE_TYPES_PATH)).map { |row| row['space_type_name'] }.freeze
    end

    # The crosswalk from prototype space types to all-level space types.
    #
    # @return [Array<Hash>] rows with :standards_building_type, :standards_space_type, :new_standards_space_type
    def self.prototype_space_type_map
      @prototype_space_type_map ||= JSON.parse(File.read(PROTOTYPE_SPACE_TYPE_MAP_PATH), symbolize_names: true).freeze
    end

    # The building type name the prototype space type map keys on.
    #
    # @param building_type [String] a standards building type
    # @return [String] the lookup name
    def self.prototype_lookup_building_type(building_type)
      case building_type
      when 'SmallOffice', 'SmallOfficeDetailed', 'MediumOffice', 'MediumOfficeDetailed', 'LargeOffice', 'LargeOfficeDetailed', 'Office'
        'Office'
      when 'RetailStandalone'
        'Retail'
      when 'RetailStripmall'
        'StripMall'
      else
        building_type
      end
    end

    # The all-level name qualified by a building type, when the vocabulary has one.
    #
    # Building types are CamelCase in the model and spaced lowercase in the vocabulary:
    # 'corridor' in a 'PrimarySchool' is 'corridor - primary school'. This is the same rule
    # resolve_space_type_properties applies when it looks a space type's properties up.
    #
    # @param name [String] an all-level space type name
    # @param building_type [String, nil] a standards building type
    # @return [String] the qualified name if it exists, else the name unchanged
    def self.all_level_name_qualified(name, building_type)
      return name if building_type.nil? || building_type.to_s.empty?

      suffix = building_type.to_s.gsub(/([a-z\d])([A-Z])/, '\1 \2').downcase
      qualified = "#{name} - #{suffix}"
      all_level_space_type_names.include?(qualified) ? qualified : name
    end

    # The level-1 name an all-level space type name belongs to.
    #
    # Qualified variants are the level-1 name followed by ' - ' segments, so the segments are
    # dropped from the right until a level-1 name remains: 'audience seating - gymnasium - primary
    # school' is 'audience seating', 'office/enclosed - > 250 sf' is 'office/enclosed'.
    #
    # @param name [String] an all-level space type name
    # @return [String, nil] the level-1 name, or nil if the name is not a typical space type
    def self.all_level_name_to_level_1(name)
      name = name.to_s.strip
      until level_1_space_type_names.include?(name)
        return nil unless name.include?(' - ')

        name = name.rpartition(' - ').first.strip
      end
      name
    end

    # The all-level space type name of a space type.
    #
    # Read from the 'standards_space_type' additional property when the typical path set it, else
    # from the standards space type. A prototype space type name ('Kitchen', 'PatRoom') is
    # translated through the prototype space type map, preferring the row for the space type's
    # standards building type, and qualified by that building type when the vocabulary has a
    # variant for it ('PatCorridor' in a Hospital is 'corridor - hospital').
    #
    # @param space_type [OpenStudio::Model::SpaceType] the space type
    # @return [String, nil] the all-level name, or nil if the space type is not a typical or prototype space type
    def self.space_type_all_level_name(space_type)
      candidates = []
      if space_type.additionalProperties.hasFeature('standards_space_type')
        candidates << space_type.additionalProperties.getFeatureAsString('standards_space_type').to_s.strip
      end
      candidates << space_type.standardsSpaceType.get.to_s.strip if space_type.standardsSpaceType.is_initialized
      candidates.reject!(&:empty?)
      return nil if candidates.empty?

      candidates.each do |name|
        return name if all_level_space_type_names.include?(name)
      end

      # a prototype space type name: translate through the crosswalk
      building_type = space_type.standardsBuildingType.is_initialized ? space_type.standardsBuildingType.get.to_s : nil
      lookup_building_type = building_type.nil? ? nil : prototype_lookup_building_type(building_type)
      candidates.each do |name|
        rows = prototype_space_type_map.select { |r| r[:standards_space_type] == name }
        next if rows.empty?

        row = rows.find { |r| r[:standards_building_type] == lookup_building_type } || rows.first
        return all_level_name_qualified(row[:new_standards_space_type], building_type)
      end
      nil
    end

    # The level-1 typical space type of a space type ('food preparation', 'patient room').
    #
    # @param space_type [OpenStudio::Model::SpaceType] the space type
    # @return [String, nil] the level-1 name, or nil if the space type cannot be classified
    def self.space_type_level_1_name(space_type)
      name = space_type_all_level_name(space_type)
      return nil if name.nil?

      all_level_name_to_level_1(name)
    end

    # Is the space type one of these typical space types?
    #
    # A level-1 name in the list ('food preparation') matches the space type and every qualified
    # variant of it; a qualified name ('corridor - hospital') matches only that variant.
    #
    # @param space_type [OpenStudio::Model::SpaceType] the space type
    # @param names [Array<String>] level-1 or all-level space type names
    # @return [Boolean] true if the space type is one of the named space types
    def self.space_type_matches?(space_type, names)
      names = Array(names)
      all_level = space_type_all_level_name(space_type)
      return false if all_level.nil?
      return true if names.include?(all_level)

      level_1 = all_level_name_to_level_1(all_level)
      !level_1.nil? && names.include?(level_1)
    end

    # The level-1 typical space type of a space.
    #
    # @param space [OpenStudio::Model::Space] the space
    # @return [String, nil] the level-1 name, or nil if the space has no classifiable space type
    def self.space_level_1_name(space)
      return nil if space.spaceType.empty?

      space_type_level_1_name(space.spaceType.get)
    end

    # Is the space one of these typical space types? See space_type_matches?.
    #
    # @param space [OpenStudio::Model::Space] the space
    # @param names [Array<String>] level-1 or all-level space type names
    # @return [Boolean] true if the space's space type is one of the named space types
    def self.space_matches?(space, names)
      return false if space.spaceType.empty?

      space_type_matches?(space.spaceType.get, names)
    end

    # The level-1 typical space types of the spaces in a thermal zone.
    #
    # @param thermal_zone [OpenStudio::Model::ThermalZone] the thermal zone
    # @return [Array<String>] unique level-1 names
    def self.thermal_zone_level_1_names(thermal_zone)
      thermal_zone.spaces.map { |space| space_level_1_name(space) }.compact.uniq
    end

    # Does the thermal zone contain a space of one of these typical space types?
    #
    # @param thermal_zone [OpenStudio::Model::ThermalZone] the thermal zone
    # @param names [Array<String>] level-1 or all-level space type names
    # @return [Boolean] true if any space in the zone is one of the named space types
    def self.thermal_zone_serves_space_types?(thermal_zone, names)
      thermal_zone.spaces.any? { |space| space_matches?(space, names) }
    end

    # Does the air loop serve a space of one of these typical space types?
    #
    # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] the air loop
    # @param names [Array<String>] level-1 or all-level space type names
    # @return [Boolean] true if any zone on the loop contains one of the named space types
    def self.air_loop_hvac_serves_space_types?(air_loop_hvac, names)
      air_loop_hvac.thermalZones.any? { |zone| thermal_zone_serves_space_types?(zone, names) }
    end

    # @!endgroup Information
  end
end
