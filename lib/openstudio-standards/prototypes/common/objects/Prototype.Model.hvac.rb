class Standard
  # Determine the typical system type given the inputs
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param area_type [String] Valid choices are residential and nonresidential
  # @param delivery_type [String] Conditioning delivery type. Valid choices are air and hydronic
  # @param heating_source [String] Valid choices are Electricity, NaturalGas, DistrictHeating, DistrictHeatingWater, DistrictHeatingSteam, DistrictAmbient
  # @param cooling_source [String] Valid choices are Electricity, DistrictCooling, DistrictAmbient
  # @param area_m2 [Double] Area in m^2
  # @param num_stories [Integer] Number of stories
  # @return [Array] An array containing the system type, central heating fuel, zone heating fuel, and cooling fuel
  def model_typical_hvac_system_type(model,
                                     climate_zone,
                                     area_type,
                                     delivery_type,
                                     heating_source,
                                     cooling_source,
                                     area_m2,
                                     num_stories)

    # Convert area to ft^2
    area_ft2 = OpenStudio.convert(area_m2, 'm^2', 'ft^2').get

    case area_type
    when 'residential'
      area_type = 'Residential'
    when 'nonresidential', 'retail', 'publicassembly', 'heatedonly'
      area_type = 'Nonresidential'
    else
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.Model.Model', "area_type '#{area_type}' invalid or missing.")
      return nil
    end

    # lookup size category
    search_criteria = {}
    search_criteria['template'] = template
    search_criteria['building_category'] = area_type
    size_data = model_find_object(standards_data['size_category'], search_criteria, nil, nil, area_ft2, num_stories)
    if size_data.nil?
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.Model.Model', "Unable to find size category for #{search_criteria}.")
      return nil
    end

    # lookup infered HVAC system type
    search_criteria = {}
    search_criteria['template'] = template
    search_criteria['size_category'] = size_data['size_category']
    search_criteria['heating_source'] = heating_source
    search_criteria['cooling_source'] = cooling_source
    search_criteria['delivery_type'] = delivery_type
    hvac_data = model_find_object(standards_data['hvac_inference'], search_criteria)

    # return system type inputs with format [type, central_heating_fuel, zone_heating_fuel, cooling_fuel]
    if hvac_data.nil? || hvac_data.empty?
      system_type_inputs = [nil, nil, nil, nil]
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', "Could not determine system type for #{area_type} building of size #{area_ft2.round} ft^2 and #{num_stories} stories, and lookups #{search_criteria}.")
    else
      system_type_inputs = [hvac_data['hvac_system_type'], hvac_data['central_heating_fuel'], hvac_data['zone_heating_fuel'], hvac_data['cooling_fuel']]
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "System type is #{system_type_inputs[0]} for #{area_type} building of size #{area_ft2.round} ft^2 and #{num_stories} stories, and lookups #{search_criteria}.")
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "--- #{system_type_inputs[1]} for main heating") unless system_type_inputs[1].nil?
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "--- #{system_type_inputs[2]} for zone heat/reheat") unless system_type_inputs[2].nil?
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "--- #{system_type_inputs[3]} for cooling") unless system_type_inputs[3].nil?
    end

    return system_type_inputs
  end

  private

  # returns the thermal zones served by the system
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param system [Hash] hash of system inputs
  # @return [Array<OpenStudio::Model::ThermalZone>] system thermal zones
  def model_get_zones_from_spaces_on_system(model, system)
    # Find all zones associated with these spaces
    thermal_zones = []
    system['space_names'].each do |space_name|
      space = model.getSpaceByName(space_name)
      if space.empty?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "No space called #{space_name} was found in the model, cannot be added to HVAC system.")
        next
      end
      space = space.get
      zone = space.thermalZone
      if zone.empty?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "Space #{space_name} has no thermal zone; cannot add an HVAC system to this space.")
        next
      end
      thermal_zones << zone.get
    end

    return thermal_zones
  end

  # returns the thermal zone that serves as the return plenum
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param system [Hash] hash of system inputs
  # @return [OpenStudio::Model::ThermalZone] the return plenum thermal zone
  def model_get_return_plenum_from_system(model, system)
    # Find the zone associated with the return plenum space name
    return_plenum = nil

    # Return nil if no return plenum
    return return_plenum if system['return_plenum'].nil?

    # Get the space
    space = model.getSpaceByName(system['return_plenum'])
    if space.empty?
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "No space called #{system['return_plenum']} was found in the model, cannot be a return plenum.")
      return return_plenum
    end
    space = space.get

    # Get the space's zone
    zone = space.thermalZone
    if zone.empty?
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.model.Model', "Space #{space.name} has no thermal zone; cannot be a return plenum.")
      return return_plenum
    end

    return zone.get
  end
end
