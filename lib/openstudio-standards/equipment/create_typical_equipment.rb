module OpenstudioStandards
  # The Equipment module provides methods to create, modify, and get information about equipment
  module Equipment
    # @!group Create Typical Equipment
    # Methods to create typical equipment

    ELECTRIC_EQUIPMENT_SPACE_TYPES_PATH = File.join(__dir__, 'data', 'electric_equipment_space_types.json')
    GAS_EQUIPMENT_SPACE_TYPES_PATH = File.join(__dir__, 'data', 'gas_equipment_space_types.json')

    # The electric equipment space type data
    #
    # @return [Array<Hash>] rows keyed by :electric_equipment_space_type_name and :standards_building_type
    def self.electric_equipment_space_type_data
      JSON.parse(File.read(ELECTRIC_EQUIPMENT_SPACE_TYPES_PATH), symbolize_names: true)
    end

    # The natural gas equipment space type data
    #
    # @return [Array<Hash>] rows keyed by :natural_gas_equipment_space_type_name and :standards_building_type
    def self.gas_equipment_space_type_data
      JSON.parse(File.read(GAS_EQUIPMENT_SPACE_TYPES_PATH), symbolize_names: true)
    end

    # The electric equipment space type names the data defines
    #
    # @return [Array<String>] unique names
    def self.electric_equipment_space_type_names
      electric_equipment_space_type_data.map { |r| r[:electric_equipment_space_type_name] }.compact.uniq
    end

    # The natural gas equipment space type names the data defines
    #
    # @return [Array<String>] unique names
    def self.gas_equipment_space_type_names
      gas_equipment_space_type_data.map { |r| r[:natural_gas_equipment_space_type_name] }.compact.uniq
    end

    # Read an equipment space type additional property into the equipment space type names it holds.
    #
    # A space type usually names one equipment space type ('kitchen'). It can name several, for
    # example a kitchen carrying both a cooking and a dishwashing object, in which case the
    # property holds a JSON array string, as written by equipment_space_type_feature_value.
    # 'na' and blank values mean no equipment.
    #
    # @param value [String, nil] the additional property value
    # @return [Array<String>] equipment space type names, possibly empty
    def self.equipment_space_type_names(value)
      return [] if value.nil?

      value = value.to_s.strip
      return [] if value.empty? || value == 'na'

      if value.start_with?('[')
        begin
          parsed = JSON.parse(value)
          return parsed.map(&:to_s).reject(&:empty?) if parsed.is_a?(Array)
        rescue JSON::ParserError
          # not an array; treat the text as one name
        end
      end
      [value]
    end

    # Encode equipment space type names for storage in a space type additional property.
    #
    # @param names [String, Array<String>] one or more equipment space type names
    # @return [String] the single name, or a JSON array string when there are several
    def self.equipment_space_type_feature_value(names)
      names = Array(names).map(&:to_s)
      return names.first if names.size == 1

      JSON.generate(names)
    end

    # Select the equipment data row for an equipment space type.
    #
    # A row keyed on the space type's own standards building type wins. Rows with no building
    # type describe equipment that is the same in every building ('bakery', 'or', or a named
    # density tier) and match a space type of any building type. When neither exists and
    # building_type_fallback is set, the median row across the building types with data is used.
    #
    # @param rows [Array<Hash>] equipment space type data
    # @param name_key [Symbol] the row key holding the equipment space type name
    # @param per_area_key [Symbol] the row key holding the power density, used to order the fallback
    # @param equipment_space_type [String] the equipment space type name to match
    # @param standards_building_type [String, nil] the space type's standards building type, if any
    # @param building_type_fallback [Boolean] allow the cross-building median when nothing matches
    # @return [Hash, nil] the selected row, or nil if there is none
    def self.select_equipment_space_type_properties(rows, name_key, per_area_key, equipment_space_type, standards_building_type, building_type_fallback: false)
      candidates = rows.select { |r| r[name_key] == equipment_space_type }
      matches = candidates.select { |r| r[:standards_building_type] == standards_building_type }
      matches = candidates.select { |r| r[:standards_building_type].nil? } if matches.empty?
      if matches.empty? && building_type_fallback
        fallback_rows = candidates.reject { |r| r[per_area_key].nil? }
        unless fallback_rows.empty?
          fallback_row = fallback_rows.sort_by { |r| r[per_area_key].to_f }[fallback_rows.size / 2]
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Equipment', "No equipment space type data for '#{equipment_space_type}' with standards_building_type #{standards_building_type}. Using the median value across building types, from standards_building_type #{fallback_row[:standards_building_type]}.")
          matches = [fallback_row]
        end
      end
      matches.first
    end

    # Replace a space type's electric equipment with the typical equipment for the named electric
    # equipment space types, one instance per name.
    #
    # @param space_type [OpenStudio::Model::SpaceType] the space type
    # @param equipment_space_types [String, Array<String>] electric equipment space type names from
    #   electric_equipment_space_types.json
    # @param building_type_fallback [Boolean] see select_equipment_space_type_properties
    # @param data [Array<Hash>, nil] the electric equipment data, loaded when nil
    # @return [Boolean] returns true if successful, false if not
    def self.space_type_apply_typical_electric_equipment(space_type, equipment_space_types, building_type_fallback: false, data: nil)
      rows = data || electric_equipment_space_type_data
      names = Array(equipment_space_types).map(&:to_s).reject { |n| n.empty? || n == 'na' }
      standards_building_type = space_type.standardsBuildingType.is_initialized ? space_type.standardsBuildingType.get : nil

      space_type.electricEquipment.sort.each(&:remove)
      names.each do |name|
        props = select_equipment_space_type_properties(rows, :electric_equipment_space_type_name, :electric_equipment_per_area, name, standards_building_type, building_type_fallback: building_type_fallback)
        if props.nil?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Equipment', "Unable to find electric equipment space type data for '#{name}' with standards_building_type #{standards_building_type}.")
          next
        end

        per_area = props[:electric_equipment_per_area].to_f
        next unless per_area > 0

        label = names.size > 1 ? "#{space_type.name} #{name}" : space_type.name.to_s
        definition = OpenStudio::Model::ElectricEquipmentDefinition.new(space_type.model)
        definition.setName("#{label} Elec Equip Definition")
        definition.setWattsperSpaceFloorArea(OpenStudio.convert(per_area, 'W/ft^2', 'W/m^2').get)
        definition.setFractionLatent(props[:electric_equipment_fraction_latent].to_f) unless props[:electric_equipment_fraction_latent].nil?
        definition.setFractionRadiant(props[:electric_equipment_fraction_radiant].to_f) unless props[:electric_equipment_fraction_radiant].nil?
        definition.setFractionLost(props[:electric_equipment_fraction_lost].to_f) unless props[:electric_equipment_fraction_lost].nil?
        instance = OpenStudio::Model::ElectricEquipment.new(definition)
        instance.setName("#{label} Elec Equip")
        instance.setSpaceType(space_type)
      end

      true
    end

    # Replace a space type's gas equipment with the typical equipment for the named natural gas
    # equipment space types, one instance per name.
    #
    # @param space_type [OpenStudio::Model::SpaceType] the space type
    # @param equipment_space_types [String, Array<String>] natural gas equipment space type names from
    #   gas_equipment_space_types.json
    # @param building_type_fallback [Boolean] see select_equipment_space_type_properties
    # @param data [Array<Hash>, nil] the gas equipment data, loaded when nil
    # @return [Boolean] returns true if successful, false if not
    def self.space_type_apply_typical_gas_equipment(space_type, equipment_space_types, building_type_fallback: false, data: nil)
      rows = data || gas_equipment_space_type_data
      names = Array(equipment_space_types).map(&:to_s).reject { |n| n.empty? || n == 'na' }
      standards_building_type = space_type.standardsBuildingType.is_initialized ? space_type.standardsBuildingType.get : nil

      space_type.gasEquipment.sort.each(&:remove)
      names.each do |name|
        props = select_equipment_space_type_properties(rows, :natural_gas_equipment_space_type_name, :gas_equipment_per_area, name, standards_building_type, building_type_fallback: building_type_fallback)
        if props.nil?
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Equipment', "Unable to find gas equipment space type data for '#{name}' with standards_building_type #{standards_building_type}.")
          next
        end

        per_area = props[:gas_equipment_per_area].to_f
        next unless per_area > 0

        label = names.size > 1 ? "#{space_type.name} #{name}" : space_type.name.to_s
        definition = OpenStudio::Model::GasEquipmentDefinition.new(space_type.model)
        definition.setName("#{label} Gas Equip Definition")
        definition.setWattsperSpaceFloorArea(OpenStudio.convert(per_area, 'Btu/hr*ft^2', 'W/m^2').get)
        definition.setFractionLatent(props[:gas_equipment_fraction_latent].to_f) unless props[:gas_equipment_fraction_latent].nil?
        definition.setFractionRadiant(props[:gas_equipment_fraction_radiant].to_f) unless props[:gas_equipment_fraction_radiant].nil?
        definition.setFractionLost(props[:gas_equipment_fraction_lost].to_f) unless props[:gas_equipment_fraction_lost].nil?
        instance = OpenStudio::Model::GasEquipment.new(definition)
        instance.setName("#{label} Gas Equip")
        instance.setSpaceType(space_type)
      end

      true
    end

    # Create typical equipment in a model
    #
    # Each space type's electric and gas equipment come from the equipment space types named in its
    # 'electric_equipment_space_type' and 'natural_gas_equipment_space_type' additional properties,
    # set from the space type data or by a load override. A property may name several equipment
    # space types (see equipment_space_type_names); each becomes its own equipment instance.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @param building_type_fallback [Boolean] when true, an equipment space type with no row for the
    #   space type's standards building type, and no building-type-agnostic row, falls back to the
    #   median value across the building types with data. Used for typical space types that do not
    #   belong to a standard building type. When false (default), unmatched space types get no equipment.
    # @return [Boolean] returns true if successful, false if not
    def self.create_typical_equipment(model, building_type_fallback: false)
      # load equipment data
      electric_rows = electric_equipment_space_type_data
      gas_rows = gas_equipment_space_type_data

      if electric_rows.nil? || gas_rows.nil?
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Equipment', 'Unable to load equipment space types data. No equipment will be added to model.')
        return false
      end

      # loop over space types and apply equipment
      model.getSpaceTypes.each do |space_type|
        # remove existing equipment objects
        space_type.electricEquipment.sort.each(&:remove)
        space_type.gasEquipment.sort.each(&:remove)

        # remove existing equipment objects from spaces
        space_type.spaces.each do |space|
          space.electricEquipment.sort.each(&:remove)
          space.gasEquipment.sort.each(&:remove)
        end

        # get equipment space types from the object
        has_electric_equipment_space_type = space_type.additionalProperties.hasFeature('electric_equipment_space_type')
        has_gas_equipment_space_type = space_type.additionalProperties.hasFeature('natural_gas_equipment_space_type')
        unless has_electric_equipment_space_type || has_gas_equipment_space_type
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Equipment', "Space type '#{space_type.name}' does not have a electric_equipment_space_type or natural_gas_equipment_space_type property assigned. Ignoring space type.")
          next
        end

        if has_electric_equipment_space_type
          names = equipment_space_type_names(space_type.additionalProperties.getFeatureAsString('electric_equipment_space_type').to_s)
          space_type_apply_typical_electric_equipment(space_type, names, building_type_fallback: building_type_fallback, data: electric_rows) unless names.empty?
        end

        if has_gas_equipment_space_type
          names = equipment_space_type_names(space_type.additionalProperties.getFeatureAsString('natural_gas_equipment_space_type').to_s)
          space_type_apply_typical_gas_equipment(space_type, names, building_type_fallback: building_type_fallback, data: gas_rows) unless names.empty?
        end
      end

      return true
    end
  end
end
