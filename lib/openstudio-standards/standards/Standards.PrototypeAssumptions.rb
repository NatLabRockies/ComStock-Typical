# Assumptions that are not set by an energy code, carried over from the DOE prototype
# buildings when the prototype tree was removed in the fork's Phase 3.
#
# These stay instance methods on Standard because create_typical, the 90.1-2019 standards
# code and ComStock's measures all call them on a Standard receiver.
class Standard
  # @!group PrototypeAssumptions

  # Creates and sets below grade wall constructions for 90.1 prototype building models. These utilize
  # CFactorUndergroundWallConstruction and require some additional parameters when compared to Construction
  #
  # @param model[OpenStudio::Model::Model] OpenStudio Model
  # @param climate_zone [String] climate zone as described for prototype models. C-Factor is based on this parameter
  # @param building_type [String] the building type
  # @param building_category [String] the building category the ground contact wall assembly is
  #   looked up under, 'Nonresidential' or 'Residential'. The construction_sets table is consulted
  #   for it only when the caller does not state it: that table has no row for an ASHRAE building
  #   type under a DEER template, and without a category this method returns before doing anything,
  #   which is how DEER models came to sit on default walls instead of C-factor assemblies.
  # @return [Boolean] returns true if successful, false if not
  def model_set_below_grade_wall_constructions(model, building_type, climate_zone, building_category: nil)
    if building_category.nil?
      # Find ground contact wall building category
      construction_set_data = model_get_construction_set(building_type)

      # If no construction data, return and allow code to use default constructions
      return false if construction_set_data.nil?

      building_category = construction_set_data['exterior_wall_building_category']
    end

    # Find wall C factor
    wall_construction_properties = model_get_construction_properties(model, 'GroundContactWall', 'Mass', building_category, climate_zone)

    # If no construction properties are found at all, return and allow code to use default constructions
    return false if wall_construction_properties.nil?

    c_factor_ip = wall_construction_properties['assembly_maximum_c_factor']

    # If no c-factor is found in construction properties, return and allow code to use defaults
    return false if c_factor_ip.nil?

    # convert to SI
    c_factor_si = c_factor_ip * OpenStudio.convert(1.0, 'Btu/ft^2*h*R', 'W/m^2*K').get

    # iterate through spaces and set any necessary CFactorUndergroundWallConstructions
    model.getSpaces.each do |space|
      # Get height of the first below grade wall in this space. Will return nil if none are found.
      below_grade_wall_height = OpenstudioStandards::Geometry.space_get_below_grade_wall_height(space)
      next if below_grade_wall_height.nil?

      c_factor_wall_name = "Basement Wall C-Factor #{c_factor_si.round(2)} Height #{below_grade_wall_height.round(2)}"

      # Check if the wall construction has been constructed already. If so, look it up in the model
      if model.getCFactorUndergroundWallConstructionByName(c_factor_wall_name).is_initialized
        basement_wall_construction = model.getCFactorUndergroundWallConstructionByName(c_factor_wall_name).get
      else
        # Create CFactorUndergroundWallConstruction objects
        basement_wall_construction = OpenStudio::Model::CFactorUndergroundWallConstruction.new(model)
        basement_wall_construction.setCFactor(c_factor_si)
        basement_wall_construction.setName(c_factor_wall_name)
        basement_wall_construction.setHeight(below_grade_wall_height)
      end

      # Set surface construction for walls adjacent to ground (i.e. basement walls)
      space.surfaces.each do |surface|
        if surface.surfaceType == 'Wall' && surface.outsideBoundaryCondition == 'OtherSideCoefficients'
          surface.setConstruction(basement_wall_construction)
          surface.setOutsideBoundaryCondition('GroundFCfactorMethod')
        end
      end
    end

    return true
  end

  # Searches a model for spaces adjacent to ground. If the slab's perimeter is adjacent to ground, the length is
  # calculated. Used for F-Factor floors that require additional parameters.
  #
  # @param model [OpenStudio Model] OpenStudio model being modified
  # @param building_type [String the building type
  # @param climate_zone [String climate zone as described for prototype models. F-Factor is based on this parameter
  # @param building_category [String] the building category the ground contact floor assembly is
  #   looked up under, 'Nonresidential' or 'Residential'. The construction_sets table is consulted
  #   for it only when the caller does not state it. This governs slab-on-grade floors, which every
  #   building has, so a template whose table has no row for the building type - a DEER template
  #   under an ASHRAE building type - left every ground floor on an uninsulated slab.
  # @return [Boolean] returns true if successful, false if not
  def model_set_floor_constructions(model, building_type, climate_zone, building_category: nil)
    if building_category.nil?
      # Find ground contact floor building category
      construction_set_data = model_get_construction_set(building_type)

      # If no construction data, return and allow code to use default constructions
      return false if construction_set_data.nil?

      building_category = construction_set_data['ground_contact_floor_building_category']
    end

    # Find floor F factor
    floor_construction_properties = model_get_construction_properties(model, 'GroundContactFloor', 'Unheated', building_category, climate_zone)

    # If no construction properties are found at all, return and allow code to use default constructions
    return false if floor_construction_properties.nil?

    f_factor_ip = floor_construction_properties['assembly_maximum_f_factor']

    # If no f-factor is found in construction properties, return and allow code to use defaults
    return false if f_factor_ip.nil?

    f_factor_si = f_factor_ip * OpenStudio.convert(1.0, 'Btu/ft*h*R', 'W/m*K').get

    # iterate through spaces and set FFactorGroundFloorConstruction to surfaces if applicable
    model.getSpaces.each do |space|
      # Find this space's exposed floor area and perimeter. NOTE: this assumes only only floor per space.
      perimeter = OpenstudioStandards::Geometry.space_get_f_floor_perimeter(space)
      area = OpenstudioStandards::Geometry.space_get_f_floor_area(space)
      next if area == 0 # skip floors not adjacent to ground

      # Record combination of perimeter and area. Each unique combination requires a FFactorGroundFloorConstruction.
      f_floor_const_name = "Foundation F #{f_factor_si.round(2)}W/m*K Perim #{perimeter.round(2)}m Area #{area.round(2)}m2"

      # Check if the floor construction has been constructed already. If so, look it up in the model
      if model.getFFactorGroundFloorConstructionByName(f_floor_const_name).is_initialized
        f_floor_construction = model.getFFactorGroundFloorConstructionByName(f_floor_const_name).get
      else
        f_floor_construction = OpenStudio::Model::FFactorGroundFloorConstruction.new(model)
        f_floor_construction.setName(f_floor_const_name)
        f_floor_construction.setFFactor(f_factor_si)
        f_floor_construction.setArea(area)
        f_floor_construction.setPerimeterExposed(perimeter)
      end

      # Set surface construction for floors adjacent to ground
      space.surfaces.each do |surface|
        if surface.surfaceType == 'Floor' && surface.outsideBoundaryCondition == 'Ground'
          surface.setConstruction(f_floor_construction)
          surface.setOutsideBoundaryCondition('GroundFCfactorMethod')
        end
      end
    end

    return true
  end

  # Adds internal mass objects and constructions based on the building type
  #
  # @param model[OpenStudio::Model::Model] OpenStudio Model
  # @param building_type [String] the building type
  # @return [Boolean] returns true if successful, false if not
  def model_add_internal_mass(model, building_type)
    # Assign a material to all internal mass objects
    material = OpenStudio::Model::StandardOpaqueMaterial.new(model)
    material.setName('Std Wood 6inch')
    material.setRoughness('MediumSmooth')
    material.setThickness(0.15)
    material.setThermalConductivity(0.12)
    material.setDensity(540)
    material.setSpecificHeat(1210)
    material.setThermalAbsorptance(0.9)
    material.setSolarAbsorptance(0.7)
    material.setVisibleAbsorptance(0.7)
    construction = OpenStudio::Model::Construction.new(model)
    construction.setName('InteriorFurnishings')
    layers = OpenStudio::Model::MaterialVector.new
    layers << material
    construction.setLayers(layers)

    # Assign the internal mass construction to existing internal mass objects
    model.getSpaces.sort.each do |space|
      internal_masses = space.internalMass
      internal_masses.each do |internal_mass|
        internal_mass.internalMassDefinition.setConstruction(construction)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Set internal mass construction for internal mass '#{internal_mass.name}' in space '#{space.name}'.")
      end
    end

    # add internal mass
    # not required for NECB2011
    unless template == 'NECB2011' ||
           building_type.include?('DataCenter') ||
           ((building_type == 'SmallHotel') &&
            (template == '90.1-2004' || template == '90.1-2007' || template == '90.1-2010' || template == '90.1-2013' || template == '90.1-2016' || template == '90.1-2019' || template == 'NREL ZNE Ready 2017'))
      internal_mass_def = OpenStudio::Model::InternalMassDefinition.new(model)
      internal_mass_def.setSurfaceAreaperSpaceFloorArea(2.0)
      internal_mass_def.setConstruction(construction)
      model.getSpaces.each do |space|
        # only add internal mass objects to conditioned spaces
        next unless OpenstudioStandards::Space.space_cooled?(space)
        next unless OpenstudioStandards::Space.space_heated?(space)

        internal_mass = OpenStudio::Model::InternalMass.new(internal_mass_def)
        internal_mass.setName("#{space.name} Mass")
        internal_mass.setSpace(space)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Added internal mass '#{internal_mass.name}' to space '#{space.name}'.")
      end
    end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Finished adding internal mass')

    return true
  end

  def model_apply_prototype_hvac_assumptions(model, building_type, climate_zone)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Started applying prototype HVAC assumptions.')

    # Fan pressure rise
    model.getFanConstantVolumes.sort.each { |obj| fan_constant_volume_apply_prototype_fan_pressure_rise(obj) }
    model.getFanVariableVolumes.sort.each { |obj| fan_variable_volume_apply_prototype_fan_pressure_rise(obj) }
    model.getFanOnOffs.sort.each { |obj| fan_on_off_apply_prototype_fan_pressure_rise(obj) }
    model.getFanZoneExhausts.sort.each { |obj| fan_zone_exhaust_apply_prototype_fan_pressure_rise(obj) }

    # Fan motor efficiency
    model.getFanConstantVolumes.sort.each { |obj| prototype_fan_apply_prototype_fan_efficiency(obj) }
    model.getFanVariableVolumes.sort.each { |obj| prototype_fan_apply_prototype_fan_efficiency(obj) }
    model.getFanOnOffs.sort.each { |obj| prototype_fan_apply_prototype_fan_efficiency(obj) }
    model.getFanZoneExhausts.sort.each { |obj| prototype_fan_apply_prototype_fan_efficiency(obj) }

    # Add Economizers
    apply_economizers(climate_zone, model)

    # Pump part load performances
    model.getPumpVariableSpeeds.sort.each { |obj| pump_variable_speed_control_type(obj) }

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Finished applying prototype HVAC assumptions.')
  end

  # Applies the Prototype Building assumptions that contradict/supersede
  # the given standard.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  def model_apply_prototype_hvac_efficiency_adjustments(model)
    building_data = model_get_building_properties(model)
    building_type = building_data['building_type']
    climate_zone = building_data['climate_zone']

    # ERVs
    if building_type == 'MidriseApartment' || building_type == 'HighriseApartment'
      # Use standalone ERV in dwelling units to provide OA
      # Loads are met by mechanical cooling and the heating system with a cycling fan
      model.getAirLoopHVACs.each do |air_loop_hvac|
        # Find out if air loop has an ERV (i.e. if heat recovery is required)
        has_erv = false
        has_erv = true if air_loop_hvac_energy_recovery?(air_loop_hvac)

        serves_res_spc = false

        air_loop_hvac.thermalZones.each do |zone|
          next unless OpenstudioStandards::ThermalZone.thermal_zone_residential?(zone)

          # Exception 3 to 6.5.6.1.1
          case template
          when '90.1-2019'
            case climate_zone
            when 'ASHRAE 169-2006-0A',
              'ASHRAE 169-2006-0B',
              'ASHRAE 169-2006-1A',
              'ASHRAE 169-2006-1B',
              'ASHRAE 169-2006-2A',
              'ASHRAE 169-2006-2B',
              'ASHRAE 169-2006-3A',
              'ASHRAE 169-2006-3B',
              'ASHRAE 169-2006-3C',
              'ASHRAE 169-2006-4A',
              'ASHRAE 169-2006-4B',
              'ASHRAE 169-2006-4C',
              'ASHRAE 169-2006-5A',
              'ASHRAE 169-2006-5B',
              'ASHRAE 169-2006-5C',
              'ASHRAE 169-2013-0A',
              'ASHRAE 169-2013-0B',
              'ASHRAE 169-2013-1A',
              'ASHRAE 169-2013-1B',
              'ASHRAE 169-2013-2A',
              'ASHRAE 169-2013-2B',
              'ASHRAE 169-2013-3A',
              'ASHRAE 169-2013-3B',
              'ASHRAE 169-2013-3C',
              'ASHRAE 169-2013-4A',
              'ASHRAE 169-2013-4B',
              'ASHRAE 169-2013-4C',
              'ASHRAE 169-2013-5A',
              'ASHRAE 169-2013-5B',
              'ASHRAE 169-2013-5C'
              if zone.floorArea <= OpenStudio.convert(500.0, 'ft^2', 'm^2').get
                has_erv = false
                OpenStudio.logFree(OpenStudio::Info, 'openstudio.Model.Model', "Energy recovery will not be modeled for the ERV serving #{zone.name}.")
              end
            end
          end

          oa_cfm_per_ft2 = 0.0578940512546562
          oa_m3_per_m2 = OpenStudio.convert(OpenStudio.convert(oa_cfm_per_ft2, 'cfm', 'm^3/s').get, '1/ft^2', '1/m^2').get
          if has_erv
            model_add_residential_erv(model, [zone], oa_m3_per_m2)
          else
            model_add_residential_ventilator(model, [zone], oa_m3_per_m2)
          end

          # Shut-off air loop level OA intake
          oa_controller = air_loop_hvac.airLoopHVACOutdoorAirSystem.get.getControllerOutdoorAir
          oa_controller.setMinimumOutdoorAirSchedule(model.alwaysOffDiscreteSchedule)

          serves_res_spc = true
        end

        if has_erv & serves_res_spc
          # Remove air loop ERV
          air_loop_hvac_remove_erv(air_loop_hvac)
        elsif has_erv
          # Apply regular adjustment if the ERV doesn't serve a residential space
          oa_sys = nil
          if air_loop_hvac.airLoopHVACOutdoorAirSystem.is_initialized
            oa_sys = air_loop_hvac.airLoopHVACOutdoorAirSystem.get
          else
            OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.AirLoopHVAC', "For #{air_loop_hvac.name}, ERV cannot be removed because the system has no OA intake.")
            return false
          end

          # Get the existing ERV or create an ERV and add it to the OA system
          oa_sys.oaComponents.each do |oa_comp|
            if oa_comp.to_HeatExchangerAirToAirSensibleAndLatent.is_initialized
              erv = oa_comp.to_HeatExchangerAirToAirSensibleAndLatent.get
              heat_exchanger_air_to_air_sensible_and_latent_apply_prototype_efficiency(erv)
            end
          end
        end
      end
    else
      # Applies the DOE Prototype Building assumption that ERVs use
      # enthalpy wheels and therefore exceed the minimum effectiveness specified by 90.1
      model.getHeatExchangerAirToAirSensibleAndLatents.each { |obj| heat_exchanger_air_to_air_sensible_and_latent_apply_prototype_efficiency(obj) }
    end

    # Update COP for large office CRAC
    # Applies the DOE Prototype Building Model (Large Office only)
    if @instvarbuilding_type == 'LargeOffice'
      model.getCoilCoolingWaterToAirHeatPumpEquationFits.sort.each do |coil_cooling_water_to_air_heat_pump|
        if coil_cooling_water_to_air_heat_pump.name.get.downcase.include?('datacenter')
          cop = coil_cooling_water_to_air_heat_pump_standard_minimum_cop(coil_cooling_water_to_air_heat_pump, rename = false, computer_room_air_conditioner = true)
          if cop.nil?
            OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "COP for #{coil_cooling_water_to_air_heat_pump.name} is not changed")
          else
            coil_cooling_water_to_air_heat_pump.setRatedCoolingCoefficientofPerformance(cop)
          end
        end
      end
    end

    return true
  end

  # Determine the prototypical economizer type for the model.
  # Defaults to FixedDryBulb based on anecdotal evidence of this being
  # the most common type encountered in the field, combined
  # with this being the default option for many equipment manufacturers,
  # and being the strategy recommended in the 2010 ASHRAE journal article
  # "Economizer High Limit Devices and Why Enthalpy Economizers Don't Work"
  # by Steven Taylor and Hwakong Cheng.
  # https://tayloreng.egnyte.com/dl/mN0c9t4WSO/ASHRAE_Journal_-_Economizer_High_Limit_Devices_and_Why_Enthalpy_Economizers_Dont_Work.pdf_
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [String] the economizer type.  Possible values are:
  # 'NoEconomizer'
  # 'FixedDryBulb'
  # 'FixedEnthalpy'
  # 'DifferentialDryBulb'
  # 'DifferentialEnthalpy'
  # 'FixedDewPointAndDryBulb'
  # 'ElectronicEnthalpy'
  # 'DifferentialDryBulbAndEnthalpy'
  def model_economizer_type(model, climate_zone)
    economizer_type = 'FixedDryBulb'
    return economizer_type
  end

  def apply_economizers(climate_zone, model)
    # Create an economizer maximum OA fraction of 70%
    # to reflect damper leakage per PNNL
    econ_max_70_pct_oa_sch = OpenStudio::Model::ScheduleRuleset.new(model)
    econ_max_70_pct_oa_sch.setName('Economizer Max OA Fraction 70 pct')
    # the controller slot this goes on does not stamp type limits, so state them here or
    # EnergyPlus reports "Schedule Type Limits Name is empty" and skips validating the values
    econ_max_70_pct_oa_sch.setScheduleTypeLimits(
      OpenstudioStandards::Schedules.create_schedule_type_limits(model, standard_schedule_type_limit: 'Fractional')
    )
    econ_max_70_pct_oa_sch.defaultDaySchedule.setName('Economizer Max OA Fraction 70 pct Default')
    econ_max_70_pct_oa_sch.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), 0.7)

    # Store original climate zones
    climate_zone_code = climate_zone

    # Check each airloop
    model.getAirLoopHVACs.sort.each do |air_loop|
      economizer_required = false

      if air_loop_hvac_humidifier_count(air_loop) > 0
        # If airloop includes a humidifier it is assumed
        # that exception c to 90.1-2004/7 Section 6.5.1 applies.
        if template == '90.1-2004' || template == '90.1-2007'
          economizer_required = false
        end
        # This exception exist through 90.1-2019, for hospitals
        # see Section 6.5.1 exception 4
        if @instvarbuilding_type == 'Hospital' &&
           (template == '90.1-2013' || template == '90.1-2016' || template == '90.1-2019')
          economizer_required = false
        end
      elsif @instvarbuilding_type == 'LargeOffice' &&
            air_loop.name.to_s.downcase.include?('datacenter') &&
            air_loop.name.to_s.downcase.include?('basement') &&
            !(template == '90.1-2004' || template == '90.1-2007')
        # System serving the data center in the basement of the large
        # office is assumed to be always large enough to require an
        # economizer when economizer requirement is based on equipment
        # size.
        #
        # No economizer modeled for 90.1-2004 and 2007:
        # Specific economizer requirements for computer rooms were
        # introduced in 90.1-2010. Before that, although not explicitly
        # specified, economizer requirements were aimed at comfort
        # cooling, not computer room cooling (as per input from the MSC).

        # Process climate zone:
        # Moisture regime is not needed for climate zone 8
        climate_zone = climate_zone.split('-')[-1]
        climate_zone = '8' if climate_zone.include?('8')

        # Get the size threshold requirement
        search_criteria = {
          'template' => template,
          'climate_zone' => climate_zone,
          'data_center' => true
        }
        econ_limits = model_find_object(standards_data['economizers'], search_criteria)
        minimum_capacity_btu_per_hr = econ_limits['minimum_capacity']
        economizer_required = !minimum_capacity_btu_per_hr.nil?
      elsif @instvarbuilding_type == 'LargeOffice' && air_loop_hvac_include_wshp?(air_loop)
        # WSHP serving the IT closets are assumed to always be too
        # small to require an economizer
        economizer_required = false
      elsif air_loop_hvac_economizer_required?(air_loop, climate_zone)
        economizer_required = true
      end

      if economizer_required
        # If an economizer is required, determine the economizer type
        # in the prototype buildings, which depends on climate zone.
        economizer_type = model_economizer_type(model, climate_zone_code)

        # Set the economizer type
        # Get the OA system and OA controller
        oa_sys = air_loop.airLoopHVACOutdoorAirSystem
        if oa_sys.is_initialized
          oa_sys = oa_sys.get
        else
          OpenStudio.logFree(OpenStudio::Error, 'openstudio.prototype.Model', "#{air_loop.name} is required to have an economizer, but it has no OA system.")
          next
        end
        oa_control = oa_sys.getControllerOutdoorAir
        oa_control.setEconomizerControlType(economizer_type)
        # oa_control.setMaximumFractionofOutdoorAirSchedule(econ_max_70_pct_oa_sch)

        # Check that the economizer type set by the prototypes
        # is not prohibited by code.  If it is, change to no economizer.
        unless air_loop_hvac_economizer_type_allowable?(air_loop, climate_zone_code)
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.prototype.Model', "#{air_loop.name} is required to have an economizer, but the type chosen, #{economizer_type} is prohibited by code for climate zone #{climate_zone}. Economizer type will be switched to No Economizer.")
          oa_control.setEconomizerControlType('NoEconomizer')
        end

      end
    end
  end

  # Set/change values of a schedule
  # Main usage is for modeling occupancy standby mode
  # where the thermostat schedule in these mode are
  # required to setup/back their thermostat setpoints
  #
  # @param time_offset_hash [Hash] Hash providing time (key) and schedule value offset (values)
  # @param schedule [OpenStudio::Model::ScheduleRuleset] OpenStudio schedule object
  # @return [OpenStudio::Model::ScheduleRuleset] Modified OpenStudio schedule object
  def model_set_schedule_value(schedule, time_value_hash)
    return nil unless schedule.to_ScheduleRuleset.is_initialized

    new_sch = schedule.clone(schedule.model).to_ScheduleRuleset.get

    # Get day schedule
    day_schedules = []
    default_day_schedule = new_sch.defaultDaySchedule
    day_schedules << default_day_schedule
    new_sch.scheduleRules.each do |rule|
      day_schedules << rule.daySchedule
    end

    # Set schedule values
    day_schedules.each do |day_schedule|
      (0..23).each do |hr|
        next if !time_value_hash.key?(hr.to_s)

        t = OpenStudio::Time.new(0, hr, 0, 0)

        # Get schedule value
        value = day_schedule.getValue(t)

        # Set schedule value
        day_schedule.addValue(t, value)
        t_p_1 = OpenStudio::Time.new(0, hr + 1, 0, 0)
        day_schedule.addValue(t_p_1, time_value_hash[hr.to_s])
      end
    end

    new_sch.setName("#{schedule.name} - adjusted")
    return new_sch
  end

    # Load a model into OpenStudio, version translating it, and log an error rather than
    # raising if the file is missing or cannot be translated.
    #
    # @param model_path_string [String] file path to an OpenStudio model file
    # @return [OpenStudio::Model::Model, Boolean] the model, or false if it could not be loaded
    def safe_load_model(model_path_string)
      model_path = OpenStudio::Path.new(model_path_string)
      unless OpenStudio.exists(model_path)
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', "#{model_path_string} couldn't be found")
        return false
      end

      version_translator = OpenStudio::OSVersion::VersionTranslator.new
      model = version_translator.loadModel(model_path)
      if model.empty?
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', "Version translation failed for #{model_path_string}")
        return false
      end

      return model.get
    end

    # Apply the loads and associated schedules to every space type in the model: rendering
    # colour, internal loads, load schedules and thermostat schedules.
    #
    # @param model [OpenStudio::Model::Model] OpenStudio model object
    # @return [Boolean] returns true if successful, false if not
    def model_add_loads(model)
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', 'Started applying space types (loads)')

      model.getSpaceTypes.sort.each do |space_type|
        space_type_apply_rendering_color(space_type)
        space_type_apply_internal_loads(space_type)
        space_type_apply_standard_internal_load_schedules(space_type)
        space_type_apply_thermostat_schedules(space_type)
      end

      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', 'Finished applying space types (loads)')

      return true
    end
  # Add exhaust fans and makeup air to the model.
  #
  # Kept as a Standard method because ComStock and the prototype-era tests call it on a
  # Standard receiver. It only delegates: the makeup air pairs it used to carry inline now
  # live in hvac/exhaust/data/exhaust_makeup_air.json, whose legacy_makeup_air section holds
  # the same building type and space type pairs.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param makeup_source [String] 'None' adds no makeup air; 'Adjacent' takes it from the
  #   thermal zone of the largest adjacent dining, cafe or cafeteria space of the same
  #   building type
  # @param remove_existing_exhaust_fans [Boolean] remove existing exhaust fans
  # @return [Array<OpenStudio::Model::FanZoneExhaust>] the zone exhaust fans
  def model_add_exhaust(model,
                        makeup_source: 'None',
                        remove_existing_exhaust_fans: true)
    OpenstudioStandards::HVAC.create_typical_exhaust(model, self,
                                                     makeup_source: makeup_source,
                                                     remove_existing_exhaust_fans: remove_existing_exhaust_fans)
  end

    # @!endgroup PrototypeAssumptions
  end
