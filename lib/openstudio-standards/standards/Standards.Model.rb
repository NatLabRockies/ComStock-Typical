require 'csv'
require 'date'
require 'parallel'

class Standard
  attr_accessor :space_multiplier_map, :standards_data

  # returns the space multiplier map

  # @return [Hash] space multiplier map
  def define_space_multiplier
    return @space_multiplier_map
  end

  # @!group Model

  # Determine whether or not the HVAC system in a model is autosized
  #
  # As it is not realistic expectation to have all autosizable
  # fields hard input, the method relies on autosizable field
  # of prime movers (fans, pumps) and heating/cooling devices
  # in the models (boilers, chillers, coils)
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if the HVAC system is likely autosized, false otherwise
  def model_is_hvac_autosized(model)
    is_hvac_autosized = false
    model.modelObjects.each do |obj|
      obj_type = obj.iddObjectType.valueName.to_s.downcase

      # Check if the object needs to be checked for autosizing
      obj_to_be_checked_for_autosizing = false
      if (obj_type.include?('chiller') || obj_type.include?('boiler') || obj_type.include?('coil') || obj_type.include?('fan') || obj_type.include?('pump') || obj_type.include?('waterheater')) && !obj_type.include?('controller')
          obj_to_be_checked_for_autosizing = true
        end

      # Check for autosizing
      if obj_to_be_checked_for_autosizing
        casted_obj = model_cast_model_object(obj)

        next if casted_obj.nil?

        casted_obj.methods.each do |method|
          if method.to_s.include?('is') && method.to_s.include?('Autosized') && (casted_obj.public_send(method) == true)
              is_hvac_autosized = true
              OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "The #{method.to_s.sub('is', '').sub('Autosized', '').sub(':', '')} field of the #{obj_type} named #{casted_obj.name} is autosized. It should be hard sized.")
            end
        end
      end
    end

    return is_hvac_autosized
  end

  # Categorize zones by occupancy type and fuel type, where the types depend on the standard.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param custom [String] custom fuel type
  # @param applicable_zones [list of zone objects]
  # @return [Array<Hash>] an array of hashes, one for each zone,
  #   with the keys 'zone', 'type' (occ type), 'fuel', and 'area'
  def model_zones_with_occ_and_fuel_type(model, custom, applicable_zones = nil)
    zones = []

    model.getThermalZones.sort.each do |zone|
      # Skip plenums
      if OpenstudioStandards::ThermalZone.thermal_zone_plenum?(zone)
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Zone #{zone.name} is a plenum.  It will not be assigned a baseline system.")
        next
      end

      # This is only used for the stable baseline (2016 and later)
      if !applicable_zones.nil? && !applicable_zones.include?(zone)
        # This zone is not part of the current hvac_building_type
        next
      end

      # Skip unconditioned zones
      heated = OpenstudioStandards::ThermalZone.thermal_zone_heated?(zone)
      cooled = OpenstudioStandards::ThermalZone.thermal_zone_cooled?(zone)
      if !heated && !cooled
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Zone #{zone.name} is unconditioned.  It will not be assigned a baseline system.")
        next
      end

      zn_hash = {}

      # The zone object
      zn_hash['zone'] = zone

      # Floor area
      zn_hash['area'] = zone.floorArea

      # Occupancy type
      zn_hash['occ'] = thermal_zone_occupancy_type(zone)

      # Building type
      zn_hash['bldg_type'] = OpenstudioStandards::ThermalZone.thermal_zone_get_building_type(zone)

      # Fuel type
      # for 2013 and prior, baseline fuel = proposed fuel
      # for 2016 and later, use fuel to identify zones with district energy
      zn_hash['fuel'] = thermal_zone_get_zone_fuels_for_occ_and_fuel_type(zone)

      zones << zn_hash
    end

    return zones
  end

  # Before deleting proposed HVAC components, determine for each zone if it has district heating
  # @return [Hash] Hash of boolean with zone name as key
  def model_get_district_heating_zones(model)
    has_district_hash = {}
    model.getThermalZones.sort.each do |zone|
      has_district_hash['building'] = false

      # error if HVACComponent heating fuels method is not available
      if model.version < OpenStudio::VersionString.new('3.6.0')
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.Standards.Model', 'Required HVACComponent method .heatingFuelTypes is not available in pre-OpenStudio 3.6.0 versions. Use a more recent version of OpenStudio.')
      end

      htg_fuels = zone.heatingFuelTypes.map(&:valueName)
      if htg_fuels.include?('DistrictHeating') || htg_fuels.include?('DistrictHeatingWater') || htg_fuels.include?('DistrictHeatingSteam')
        has_district_hash[zone.name] = true
        has_district_hash['building'] = true
      else
        has_district_hash[zone.name] = false
      end
    end
    return has_district_hash
  end

  # Get list of heat types across a list of zones
  # @param zones [array of objects] array of zone objects
  # @return [String concatenated string showing different fuel types in a group of zones
  def get_group_heat_types(model, zones)
    heat_list = ''
    has_district_heat = false
    has_fuel_heat = false
    has_electric_heat = false
    zones.each do |zone|
      if OpenstudioStandards::ThermalZone.thermal_zone_district_heat?(zone)
        has_district_heat = true
      end
      if OpenstudioStandards::ThermalZone.thermal_zone_fossil_heat?(zone)
        has_fuel_heat = true
      end
      if OpenstudioStandards::ThermalZone.thermal_zone_electric_heat?(zone)
        has_electric_heat = true
      end
    end

    if has_district_heat
      heat_list = 'districtheating'
    end
    if has_fuel_heat
      heat_list += '_fuel'
    end
    if has_electric_heat
      heat_list += '_electric'
    end
    return heat_list
  end

  # Store fan operation schedule for each zone before deleting HVAC objects
  # @author Doug Maddox, PNNL
  # @param model [object]
  # @return [Hash] of zoneName:fan_schedule_8760
  def get_fan_schedule_for_each_zone(model)
    fan_sch_names = {}

    # Start with air loops
    model.getAirLoopHVACs.sort.each do |air_loop_hvac|
      fan_schedule_8760 = []
      # Check for availability managers
      # Assume only AvailabilityManagerScheduled will control fan schedule
      # @todo also check AvailabilityManagerScheduledOn
      avail_mgrs = air_loop_hvac.availabilityManagers
      # if avail_mgrs.is_initialized
      if !avail_mgrs.nil?
        avail_mgrs.each do |avail_mgr|
          # avail_mgr = avail_mgr.get
          # Check each type of AvailabilityManager
          # If the current one matches, get the fan schedule
          if avail_mgr.to_AvailabilityManagerScheduled.is_initialized
            avail_mgr = avail_mgr.to_AvailabilityManagerScheduled.get
            fan_schedule = avail_mgr.schedule
            # fan_sch_translator = ScheduleTranslator.new(model, fan_schedule)
            # fan_sch_ruleset = fan_sch_translator.translate
            fan_schedule_8760 = OpenstudioStandards::Schedules.schedule_get_hourly_values(fan_schedule)
          end
        end
      end
      if fan_schedule_8760.empty?
        # If there are no availability managers, then use the schedule in the supply fan object
        # Note: testing showed that the fan object schedule is not used by OpenStudio
        # Instead, get the fan schedule from the air_loop_hvac object
        # fan_object = nil
        # fan_object = get_fan_object_for_airloop(model, air_loop_hvac)
        fan_object = 'nothing'
        if fan_object.nil?
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Failed to retreive fan object for AirLoop #{air_loop_hvac.name}")
        else
          # fan_schedule = fan_object.availabilitySchedule
          fan_schedule = air_loop_hvac.availabilitySchedule
        end
        fan_schedule_8760 = OpenstudioStandards::Schedules.schedule_get_hourly_values(fan_schedule)
      end

      # Assign this schedule to each zone on this air loop
      air_loop_hvac.thermalZones.each do |zone|
        fan_sch_names[zone.name.get] = fan_schedule_8760
      end
    end

    # Handle Zone equipment
    model.getThermalZones.sort.each do |zone|
      if !fan_sch_names.key?(zone.name.get)
        # This zone was not assigned a schedule via air loop
        # Check for zone equipment fans
        zone.equipment.each do |zone_equipment|
          next if zone_equipment.to_FanZoneExhaust.is_initialized

          # get fan schedule
          fan_object = zone_hvac_get_fan_object(zone_equipment)
          if !fan_object.nil?
            fan_schedule = fan_object.availabilitySchedule
            fan_schedule_8760 = OpenstudioStandards::Schedules.schedule_get_hourly_values(fan_schedule)
            fan_sch_names[zone.name.get] = fan_schedule_8760
            break
          end
        end
      end
    end

    return fan_sch_names
  end

  # Get the supply fan object for an air loop
  # @author Doug Maddox, PNNL
  # @param model [object]
  # @param air_loop [object]
  # @return [object] supply fan of zone equipment component
  def get_fan_object_for_airloop(model, air_loop)
    if air_loop.supplyFan.empty?
      # Check if system has unitary wrapper
      air_loop.supplyComponents.each do |component|
        # Get the object type, getting the internal coil
        # type if inside a unitary system.
        obj_type = component.iddObjectType.valueName.to_s
        fan_component = nil
        case obj_type
        when 'OS_AirLoopHVAC_UnitaryHeatCool_VAVChangeoverBypass'
          component = component.to_AirLoopHVACUnitaryHeatCoolVAVChangeoverBypass.get
          fan_component = component.supplyFan.get
        when 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir'
          component = component.to_AirLoopHVACUnitaryHeatPumpAirToAir.get
          fan_component = component.supplyFan.get
        when 'OS_AirLoopHVAC_UnitaryHeatPump_AirToAir_MultiSpeed'
          component = component.to_AirLoopHVACUnitaryHeatPumpAirToAirMultiSpeed.get
          fan_component = component.supplyFan.get
        when 'OS_AirLoopHVAC_UnitarySystem'
          component = component.to_AirLoopHVACUnitarySystem.get
          fan_component = component.supplyFan.get
        end

        if !fan_component.nil?
          break
        end
      end
    else
      fan_component = air_loop.supplyFan.get
    end

    # Get the fan object for this fan
    fan_obj_type = fan_component.iddObjectType.valueName.to_s
    case fan_obj_type
    when 'OS_Fan_OnOff'
      fan_obj = fan_component.to_FanOnOff.get
    when 'OS_Fan_ConstantVolume'
      fan_obj = fan_component.to_FanConstantVolume.get
    when 'OS_Fan_SystemModel'
      fan_obj = fan_component.to_FanSystemModel.get
    when 'OS_Fan_VariableVolume'
      fan_obj = fan_component.to_FanVariableVolume.get
    end
    return fan_obj
  end

  # elimates outlier zones based on a set of keys
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param array_of_zones [Array] an array of Hashes for each zone, with the keys 'zone'
  # @param key_to_inspect [String] hash key to inspect in array of zones
  # @param tolerance [Double] tolerance
  # @param field_name [String] field name to inspect
  # @param units [String] units
  # @return [Array] an array of Hashes for each zone
  def model_eliminate_outlier_zones(model, array_of_zones, key_to_inspect, tolerance, field_name, units)
    # Sort the zones by the desired key
    begin
      array_of_zones = array_of_zones.sort_by { |hsh| hsh[key_to_inspect] }
    rescue ArgumentError => e
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Unable to sort array_of_zones by #{key_to_inspect} due to #{e.message}, defaulting to order that was passed")
    end

    # Calculate the area-weighted average
    total = 0.0
    total_area = 0.0
    all_vals = []
    all_areas = []
    all_zn_names = []
    array_of_zones.each do |zn|
      val = zn[key_to_inspect]
      area = zn['area_ft2']
      total += val * area
      total_area += area
      all_vals << val.round(1)
      all_areas << area.round
      all_zn_names << zn['zone'].name.get.to_s
    end

    if total_area == 0
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', "Total area is zero for array_of_zones with key #{key_to_inspect}, unable to calculate area-weighted average.")
      return false
    end

    avg = total / total_area
    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Model', "Values for #{field_name}, tol = #{tolerance} #{units}, area ft2:")
    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Model', "vals  #{all_vals.join(', ')}")
    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Model', "areas #{all_areas.join(', ')}")
    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Model', "names #{all_zn_names.join(', ')}")

    # Calculate the biggest delta and the index of the biggest delta
    biggest_delta_i = 0 # array at first item in case delta is 0
    biggest_delta = 0.0
    worst = nil
    array_of_zones.each_with_index do |zn, i|
      val = zn[key_to_inspect]
      if worst.nil? # array at first item in case delta is 0
        worst = val
      end
      delta = (val - avg).abs
      if delta >= biggest_delta
        biggest_delta = delta
        biggest_delta_i = i
        worst = val
      end
    end

    # puts "   #{worst} - #{avg.round} = #{biggest_delta.round} biggest delta"

    # Compare the biggest delta against the difference and eliminate that zone if higher than the limit.
    if biggest_delta > tolerance
      zn_name = array_of_zones[biggest_delta_i]['zone'].name.get.to_s
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "For zone #{zn_name}, the #{field_name} of #{worst.round(1)} #{units} is more than #{tolerance} #{units} outside the area-weighted average of #{avg.round(1)} #{units}; it will be placed on its own secondary system.")
      array_of_zones.delete_at(biggest_delta_i)
      # Call method recursively if something was eliminated
      array_of_zones = model_eliminate_outlier_zones(model, array_of_zones, key_to_inspect, tolerance, field_name, units)
    else
      zn_name = array_of_zones[biggest_delta_i]['zone'].name.get.to_s
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "For zone #{zn_name}, the #{field_name} #{worst.round(2)} #{units} - average #{field_name} #{avg.round(2)} #{units} = #{biggest_delta.round(2)} #{units} less than the tolerance of #{tolerance} #{units}, stopping elimination process.")
    end

    return array_of_zones
  end

  # Determine which of the zones should be served by the primary HVAC system.
  # First, eliminate zones that differ by more# than 40 full load hours per week.
  # In this case, lighting schedule is used as the proxy for operation instead
  # of occupancy to avoid accidentally removing transition spaces.
  # Second, eliminate zones whose design internal loads differ from the area-weighted average of all other zones
  # on the system by more than 10 Btu/hr*ft^2.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param zones [Array<OpenStudio::Model::ThermalZone>] an array of zones
  # @return [Hash] A hash of two arrays of ThermalZones,
  # where the keys are 'primary' and 'secondary'
  def model_differentiate_primary_secondary_thermal_zones(model, zones, zone_fan_scheds = nil)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', 'Determining which zones are served by the primary vs. secondary HVAC system.')

    # Determine the operational hours (proxy is annual
    # full load lighting hours) for all zones
    zone_data_1 = []
    zones.each do |zone|
      data = {}
      data['zone'] = zone
      # Get the area
      area_ft2 = OpenStudio.convert(zone.floorArea * zone.multiplier, 'm^2', 'ft^2').get
      data['area_ft2'] = area_ft2
      # OpenStudio::logFree(OpenStudio::Info, "openstudio.Standards.Model", "#{zone.name}")
      zone.spaces.each do |space|
        # OpenStudio::logFree(OpenStudio::Info, "openstudio.Standards.Model", "***#{space.name}")
        # Get all lights from either the space
        # or the space type.
        all_lights = []
        all_lights += space.lights
        if space.spaceType.is_initialized
          all_lights += space.spaceType.get.lights
        end
        # Base the annual operational hours
        # on the first lights schedule with hours
        # greater than zero.
        ann_op_hrs = 0
        all_lights.sort.each do |lights|
          # OpenStudio::logFree(OpenStudio::Info, "openstudio.Standards.Model", "******#{lights.name}")
          # Get the fractional lighting schedule
          lights_sch = lights.schedule
          full_load_hrs = 0.0
          # Skip lights with no schedule
          next if lights_sch.empty?

          lights_sch = lights_sch.get
          full_load_hrs = OpenstudioStandards::Schedules.schedule_get_equivalent_full_load_hours(lights_sch)
          if full_load_hrs > 0
            ann_op_hrs = full_load_hrs
            break # Stop after the first schedule with more than 0 hrs
          end
        end
        wk_op_hrs = ann_op_hrs / 52.0
        data['wk_op_hrs'] = wk_op_hrs
        # OpenStudio::logFree(OpenStudio::Info, "openstudio.Standards.Model", "******wk_op_hrs = #{wk_op_hrs.round}")
      end

      zone_data_1 << data
    end

    # Filter out any zones that operate differently by more than 40hrs/wk.
    # This will be determined by a difference of more than (40 hrs/wk * 52 wks/yr) = 2080 annual full load hrs.
    zones_same_hrs = model_eliminate_outlier_zones(model, zone_data_1, 'wk_op_hrs', 40, 'weekly operating hrs', 'hrs')

    # Get the internal loads for
    # all remaining zones.
    zone_data_2 = []
    zones_same_hrs.each do |zn_data|
      data = {}
      zone = zn_data['zone']
      data['zone'] = zone
      # Get the area
      area_m2 = zone.floorArea * zone.multiplier
      area_ft2 = OpenStudio.convert(area_m2, 'm^2', 'ft^2').get
      data['area_ft2'] = area_ft2
      # Get the internal loads
      int_load_w = OpenstudioStandards::ThermalZone.thermal_zone_get_design_internal_load(zone) * zone.multiplier
      # Normalize per-area
      int_load_w_per_m2 = int_load_w / area_m2
      int_load_btu_per_ft2 = OpenStudio.convert(int_load_w_per_m2, 'W/m^2', 'Btu/hr*ft^2').get
      data['int_load_btu_per_ft2'] = int_load_btu_per_ft2
      zone_data_2 << data
    end

    # Filter out any zones that are +/- 10 Btu/hr*ft^2 from the average
    pri_zn_data = model_eliminate_outlier_zones(model, zone_data_2, 'int_load_btu_per_ft2', 10, 'internal load', 'Btu/hr*ft^2')

    # Get just the primary zones themselves
    pri_zones = []
    pri_zone_names = []
    pri_zn_data.each do |zn_data|
      pri_zones << zn_data['zone']
      pri_zone_names << zn_data['zone'].name.get.to_s
    end

    # Get the secondary zones
    sec_zones = []
    sec_zone_names = []
    zones.each do |zone|
      unless pri_zones.include?(zone)
        sec_zones << zone
        sec_zone_names << zone.name.get.to_s
      end
    end

    # Report out the primary vs. secondary zones
    unless pri_zone_names.empty?
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Primary system zones = #{pri_zone_names.join(', ')}.")
    end
    unless sec_zone_names.empty?
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Secondary system zones = #{sec_zone_names.join(', ')}.")
    end

    zone_op_hrs = []
    return { 'primary' => pri_zones, 'secondary' => sec_zones, 'zone_op_hrs' => zone_op_hrs }
  end

  # For a multizone system, get straight average of hash values excluding the reference zone
  # @author Doug Maddox, PNNL
  # @param value_hash [Hash<String>] of zoneName:Value
  # @param ref_zone [String] name of reference zone
  def get_avg_of_other_zones(value_hash, ref_zone)
    num_others = value_hash.size - 1
    value_sum = 0
    value_hash.each do |key, val|
      value_sum += val unless key == ref_zone
    end
    if num_others == 0
      value_avg = value_hash[ref_zone]
    else
      value_avg = value_sum / num_others
    end
    return value_avg
  end

  # For a multizone system, get area weighted average of hash values excluding the reference zone
  # @author Doug Maddox, PNNL
  # @param value_hash [Hash<String>] of zoneName:Value
  # @param area_hash [Hash<String>] of zoneName:Area
  # @param ref_zone [String] name of reference zone
  def get_wtd_avg_of_other_zones(value_hash, area_hash, ref_zone)
    num_others = value_hash.size - 1
    value_sum = 0
    area_sum = 0
    value_hash.each do |key, val|
      value_sum += val * area_hash[key] unless key == ref_zone
      area_sum += area_hash[key] unless key == ref_zone
    end
    if num_others == 0
      value_avg = value_hash[ref_zone]
    else
      value_avg = value_sum / area_sum
    end
    return value_avg
  end

  # For a multizone system, create the fan schedule based on zone occupancy/fan schedules
  # @author Doug Maddox, PNNL
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param zone_op_hrs [Hash] hash of zoneName zone_op_hrs
  # @param pri_zones [Array<String>] names of zones served by the multizone system
  # @param system_name [String] name of air loop
  def model_create_multizone_fan_schedule(model, zone_op_hrs, pri_zones, system_name)
    # Not applicable if not stable baseline
    return
  end

  # Applies the multi-zone VAV outdoor air sizing requirements to all applicable air loops in the model.
  # @note This must be performed before the sizing run because it impacts component sizes, which in turn impact efficiencies.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def model_apply_multizone_vav_outdoor_air_sizing(model)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Started applying multizone vav OA sizing.')

    # Multi-zone VAV outdoor air sizing
    model.getAirLoopHVACs.sort.each { |obj| air_loop_hvac_apply_multizone_vav_outdoor_air_sizing(obj) }

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Finished applying multizone vav OA sizing.')
  end

  # Raise every VAV terminal's minimum airflow to cover its zone's design outdoor air.
  # Needs a sizing run first where terminal maximum flows are autosized.
  # See air_loop_hvac_apply_vav_terminal_minimum_outdoor_air.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Integer] the number of terminals whose minimum was raised
  def model_apply_vav_terminal_minimum_outdoor_air(model)
    raised = model.getAirLoopHVACs.sort.sum { |air_loop| air_loop_hvac_apply_vav_terminal_minimum_outdoor_air(air_loop) }
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Raised the minimum airflow of #{raised} VAV terminals to cover their zone outdoor air.") if raised > 0
    return raised
  end

  # Applies the HVAC parts of the template to all objects in the model using the the template specified in the model.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @param apply_controls [Boolean] toggle whether to apply air loop and plant loop controls
  # @param sql_db_vars_map [Hash] hash map
  # @return [Boolean] returns true if successful, false if not
  def model_apply_hvac_efficiency_standard(model, climate_zone, apply_controls: true, sql_db_vars_map: nil)
    sql_db_vars_map = {} if sql_db_vars_map.nil?

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Started applying HVAC efficiency standards for #{template} template.")

    # Air Loop Controls
    if apply_controls.nil? || apply_controls == true
      model.getAirLoopHVACs.sort.each { |obj| air_loop_hvac_apply_standard_controls(obj, climate_zone) }
    end

    # Plant Loop Controls
    if apply_controls.nil? || apply_controls == true
      model.getPlantLoops.sort.each { |obj| plant_loop_apply_standard_controls(obj, climate_zone) }
    end

    # Zone HVAC Controls
    model.getZoneHVACComponents.sort.each { |obj| zone_hvac_component_apply_standard_controls(obj) }

    ##### Apply equipment efficiencies

    # Fans
    model.getFanVariableVolumes.sort.each { |obj| fan_apply_standard_minimum_motor_efficiency(obj, fan_brake_horsepower(obj)) }
    model.getFanConstantVolumes.sort.each { |obj| fan_apply_standard_minimum_motor_efficiency(obj, fan_brake_horsepower(obj)) }
    model.getFanOnOffs.sort.each { |obj| fan_apply_standard_minimum_motor_efficiency(obj, fan_brake_horsepower(obj)) }
    model.getFanZoneExhausts.sort.each { |obj| fan_apply_standard_minimum_motor_efficiency(obj, fan_brake_horsepower(obj)) }

    # Pumps
    model.getPumpConstantSpeeds.sort.each { |obj| pump_apply_standard_minimum_motor_efficiency(obj) }
    model.getPumpVariableSpeeds.sort.each { |obj| pump_apply_standard_minimum_motor_efficiency(obj) }
    model.getHeaderedPumpsConstantSpeeds.sort.each { |obj| pump_apply_standard_minimum_motor_efficiency(obj) }
    model.getHeaderedPumpsVariableSpeeds.sort.each { |obj| pump_apply_standard_minimum_motor_efficiency(obj) }

    # Unitary HPs
    # set DX HP coils before DX clg coils because when DX HP coils need to first
    # pull the capacities of their paired DX clg coils, and this does not work
    # correctly if the DX clg coil efficiencies have been set because they are renamed.
    model.getCoilHeatingDXSingleSpeeds.sort.each { |obj| sql_db_vars_map = coil_heating_dx_single_speed_apply_efficiency_and_curves(obj, sql_db_vars_map) }

    # Unitary ACs
    model.getCoilCoolingDXTwoSpeeds.sort.each { |obj| sql_db_vars_map = coil_cooling_dx_two_speed_apply_efficiency_and_curves(obj, sql_db_vars_map) }
    model.getCoilCoolingDXSingleSpeeds.sort.each { |obj| sql_db_vars_map = coil_cooling_dx_single_speed_apply_efficiency_and_curves(obj, sql_db_vars_map) }
    model.getCoilCoolingDXMultiSpeeds.sort.each { |obj| sql_db_vars_map = coil_cooling_dx_multi_speed_apply_efficiency_and_curves(obj, sql_db_vars_map) }

    # WSHPs
    # set WSHP heating coils before cooling coils to get cooling coil capacities before they are renamed
    model.getCoilHeatingWaterToAirHeatPumpEquationFits.sort.each { |obj| sql_db_vars_map = coil_heating_water_to_air_heat_pump_apply_efficiency_and_curves(obj, sql_db_vars_map) }
    model.getCoilCoolingWaterToAirHeatPumpEquationFits.sort.each { |obj| sql_db_vars_map = coil_cooling_water_to_air_heat_pump_apply_efficiency_and_curves(obj, sql_db_vars_map) }

    # Chillers
    clg_tower_objs = model.getCoolingTowerSingleSpeeds
    model.getChillerElectricEIRs.sort.each { |obj| chiller_electric_eir_apply_efficiency_and_curves(obj, clg_tower_objs) }

    # Boilers
    model.getBoilerHotWaters.sort.each { |obj| boiler_hot_water_apply_efficiency_and_curves(obj) }

    # Water Heaters
    model.getWaterHeaterMixeds.sort.each { |obj| water_heater_mixed_apply_efficiency(obj) }

    # Cooling Towers
    model.getCoolingTowerSingleSpeeds.sort.each { |obj| cooling_tower_single_speed_apply_efficiency_and_curves(obj) }
    model.getCoolingTowerTwoSpeeds.sort.each { |obj| cooling_tower_two_speed_apply_efficiency_and_curves(obj) }
    model.getCoolingTowerVariableSpeeds.sort.each { |obj| cooling_tower_variable_speed_apply_efficiency_and_curves(obj) }

    # Fluid Coolers
    model.getFluidCoolerSingleSpeeds.sort.each { |obj| fluid_cooler_apply_minimum_power_per_flow(obj, equipment_type: 'Dry Cooler') }
    model.getFluidCoolerTwoSpeeds.sort.each { |obj| fluid_cooler_apply_minimum_power_per_flow(obj, equipment_type: 'Dry Cooler') }
    model.getEvaporativeFluidCoolerSingleSpeeds.sort.each { |obj| fluid_cooler_apply_minimum_power_per_flow(obj, equipment_type: 'Closed Cooling Tower') }
    model.getEvaporativeFluidCoolerTwoSpeeds.sort.each { |obj| fluid_cooler_apply_minimum_power_per_flow(obj, equipment_type: 'Closed Cooling Tower') }

    # ERVs
    model.getHeatExchangerAirToAirSensibleAndLatents.each { |obj| heat_exchanger_air_to_air_sensible_and_latent_apply_effectiveness(obj) }

    # Gas Heaters
    model.getCoilHeatingGass.sort.each { |obj| coil_heating_gas_apply_efficiency_and_curves(obj) }
    model.getCoilHeatingGasMultiStages.each { |obj| coil_heating_gas_multi_stage_apply_efficiency_and_curves(obj) }

    # VRFs
    model.getAirConditionerVariableRefrigerantFlows.sort.each { |obj| air_conditioner_variable_refrigerant_flow_apply_efficiency_and_curves(obj) }

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Finished applying HVAC efficiency standards for #{template} template.")
    return true
  end

  # Applies daylighting controls to each space in the model per the standard.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def model_add_daylighting_controls(model)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Started adding daylighting controls.')

    # Add daylighting controls to each space
    model.getSpaces.sort.each do |space|
      added = space_add_daylighting_controls(space, true, false)
    end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', 'Finished adding daylighting controls.')
    return true
  end

  # Default 5-sided (exterior walls and roof) airtightness design value (m^3/h-m^2) from a building pressurization test at 75 Pascals.
  def default_airtightness
    airtightness_value = 13.8
    return airtightness_value
  end

  # Buildings by default are assumed to not have an air barrier
  def default_air_barrier
    return false
  end

  # Get the maximum value for a field of a hash
  #
  # @param hash_of_objects [Hash] hash of objects to search through
  # @param field [String] field name from the hash
  # @return [float] Return the first matching object hash if successful, nil if not.
  def model_find_maximum_value(hash_of_objects, field)
    maximum_value = 0
    hash_of_objects.each do |set|
      maximum_value = [maximum_value, set[field]].max if set[field].to_f > 0
    end
    return maximum_value
  end

  # Method to search through a hash for the objects that meets the desired search criteria, as passed via a hash.
  # Returns an Array (empty if nothing found) of matching objects.
  #
  # @param hash_of_objects [Hash] hash of objects to search through
  # @param search_criteria [Hash] hash of search criteria
  # @param capacity [Double] capacity of the object in question.  If capacity is supplied,
  #   the objects will only be returned if the specified capacity is between the minimum_capacity and maximum_capacity values.
  # @param date [<OpenStudio::Date>] date of the object in question.  If date is supplied,
  #   the objects will only be returned if the specified date is between the start_date and end_date.
  # @param area [Double] area of the object in question.  If area is supplied,
  #   the objects will only be returned if the specified area is between the minimum_area and maximum_area values.
  # @param num_floors [Double] capacity of the object in question.  If num_floors is supplied,
  #   the objects will only be returned if the specified num_floors is between the minimum_floors and maximum_floors values.
  # @param fan_motor_bhp [Double] fan motor brake horsepower.
  # @param volume [Double] Equipment storage capacity in gallons.
  # @param capacity_per_volume [Double] Equipment capacity per storage capacity in Btu/h/gal.
  # @return [Array] returns an array of hashes, one hash per object.  Array is empty if no results.
  # @example Find all the schedule rules that match the name
  #   rules = model_find_objects(standards_data['schedules'], 'name' => schedule_name)
  #   if rules.empty?
  #     OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', "Cannot find data for schedule: #{schedule_name}, will not be created.")
  #     return false
  #   end
  def model_find_objects(hash_of_objects, search_criteria, capacity = nil, date = nil, area = nil, num_floors = nil, fan_motor_bhp = nil, volume = nil, capacity_per_volume = nil)
    matching_objects = []
    if hash_of_objects.is_a?(Hash) && hash_of_objects.key?('table')
      hash_of_objects = hash_of_objects['table']
    end

    # Compare each of the objects against the search criteria
    raise("This is not a table #{hash_of_objects}") unless hash_of_objects.respond_to?(:each)

    hash_of_objects.each do |object|
      meets_all_search_criteria = true
      search_criteria.each do |key, value|
        # Don't check non-existent search criteria
        next unless object.key?(key)

        # Stop as soon as one of the search criteria is not met
        # 'Any' is a special key that matches anything
        unless object[key] == value || object[key] == 'Any'
          meets_all_search_criteria = false
          break
        end
      end
      # Skip objects that don't meet all search criteria
      next unless meets_all_search_criteria

      # If made it here, object matches all search criteria
      matching_objects << object
    end

    # If capacity was specified, narrow down the matching objects
    unless capacity.nil?
      # Skip objects that don't have fields for minimum_capacity and maximum_capacity
      matching_objects = matching_objects.reject { |object| !object.key?('minimum_capacity') || !object.key?('maximum_capacity') }

      # Skip objects that don't have values specified for minimum_capacity and maximum_capacity
      matching_objects = matching_objects.reject { |object| object['minimum_capacity'].nil? || object['maximum_capacity'].nil? }

      # Convert to a float in case not already
      capacity = capacity.to_f

      # Skip objects whose the minimum capacity is below or maximum capacity above the specified capacity
      matching_capacity_objects = matching_objects.reject { |object| capacity <= object['minimum_capacity'].to_f || capacity > object['maximum_capacity'].to_f }

      # If no object was found, round the capacity down in case the number fell between the limits in the json file.
      if matching_capacity_objects.empty?
        capacity *= 0.99
        # Skip objects whose minimum capacity is below or maximum capacity above the specified capacity
        matching_objects = matching_objects.reject { |object| capacity <= object['minimum_capacity'].to_f || capacity > object['maximum_capacity'].to_f }
      else
        matching_objects = matching_capacity_objects
      end
    end

    # If volume was specified, narrow down the matching objects
    unless volume.nil?
      # Skip objects that don't have fields for minimum_storage and maximum_storage
      matching_objects = matching_objects.reject { |object| !object.key?('minimum_storage') || !object.key?('maximum_storage') }

      # Skip objects that don't have values specified for minimum_storage and maximum_storage
      matching_objects = matching_objects.reject { |object| object['minimum_storage'].nil? || object['maximum_storage'].nil? }

      # Skip objects whose the minimum volume is below or maximum volume above the specified volume
      matching_volume_objects = matching_objects.reject { |object| volume.to_f < object['minimum_storage'].to_f || volume.to_f > object['maximum_storage'].to_f }

      # If no object was found, round the volume down in case the number fell between the limits in the json file.
      if matching_volume_objects.empty?
        volume *= 0.99
        # Skip objects whose minimum volume is below or maximum volume above the specified volume
        matching_objects = matching_objects.reject { |object| volume.to_f <= object['minimum_storage'].to_f || volume.to_f >= object['maximum_storage'].to_f }
      else
        matching_objects = matching_volume_objects
      end
    end

    # If capacity_per_volume was specified, narrow down the matching objects
    unless capacity_per_volume.nil?
      # Skip objects that don't have fields for minimum_capacity_per_storage and maximum_capacity_per_storage
      matching_objects = matching_objects.reject { |object| !object.key?('minimum_capacity_per_storage') || !object.key?('maximum_capacity_per_storage') }

      # Skip objects that don't have values specified for minimum_capacity_per_storage and maximum_capacity_per_storage
      matching_objects = matching_objects.reject { |object| object['minimum_capacity_per_storage'].nil? || object['maximum_capacity_per_storage'].nil? }

      # Skip objects whose the minimum capacity_per_volume is below or maximum capacity_per_volume above the specified capacity_per_volume
      matching_capacity_per_volume_objects = matching_objects.reject { |object| capacity_per_volume.to_f <= object['minimum_capacity_per_storage'].to_f || capacity_per_volume.to_f >= object['maximum_capacity_per_storage'].to_f }

      # If no object was found, round the volume down in case the number fell between the limits in the json file.
      if matching_capacity_per_volume_objects.empty?
        capacity_per_volume *= 0.99
        # Skip objects whose minimum capacity_per_volume is below or maximum capacity_per_volume above the specified capacity_per_volume
        matching_objects = matching_objects.reject { |object| capacity_per_volume.to_f <= object['minimum_capacity_per_storage'].to_f || capacity_per_volume.to_f >= object['maximum_capacity_per_storage'].to_f }
      else
        matching_objects = matching_capacity_per_volume_objects
      end
    end

    # If fan_motor_bhp was specified, narrow down the matching objects
    unless fan_motor_bhp.nil?
      # Skip objects that don't have fields for minimum_capacity and maximum_capacity
      matching_objects = matching_objects.reject { |object| !object.key?('minimum_capacity') || !object.key?('maximum_capacity') }

      # Skip objects that don't have values specified for minimum_capacity and maximum_capacity
      matching_objects = matching_objects.reject { |object| object['minimum_capacity'].nil? || object['maximum_capacity'].nil? }

      # Skip objects whose the minimum capacity is below or maximum capacity above the specified fan_motor_bhp
      matching_capacity_objects = matching_objects.reject { |object| fan_motor_bhp.to_f <= object['minimum_capacity'].to_f || fan_motor_bhp.to_f > object['maximum_capacity'].to_f }

      # Filter based on motor type
      matching_capacity_objects = matching_capacity_objects.select { |object| object['type'].to_s.downcase == search_criteria['type'].to_s.downcase } if search_criteria.keys.include?('type')

      # If no object was found, round the fan_motor_bhp down in case the number fell between the limits in the json file.
      if matching_capacity_objects.empty?
        fan_motor_bhp *= 0.99
        # Skip objects whose minimum capacity is below or maximum capacity above the specified fan_motor_bhp
        matching_objects = matching_objects.reject { |object| fan_motor_bhp.to_f <= object['minimum_capacity'].to_f || fan_motor_bhp.to_f > object['maximum_capacity'].to_f }
      else
        matching_objects = matching_capacity_objects
      end
    end

    # If date was specified, narrow down the matching objects
    unless date.nil?
      # Skip objects that don't have fields for start_date and end_date
      matching_objects = matching_objects.reject { |object| !object.key?('start_date') || !object.key?('end_date') }

      # Skip objects whose start date is earlier than the specified date
      matching_objects = matching_objects.reject { |object| date <= Date.parse(object['start_date']) }

      # Skip objects whose end date is later than the specified date
      matching_objects = matching_objects.reject { |object| date > Date.parse(object['end_date']) }
    end

    # If area was specified, narrow down the matching objects
    unless area.nil?
      # Skip objects that don't have fields for minimum_area and maximum_area
      matching_objects = matching_objects.reject { |object| !object.key?('minimum_area') || !object.key?('maximum_area') }

      # Skip objects that don't have values specified for minimum_area and maximum_area
      matching_objects = matching_objects.reject { |object| object['minimum_area'].nil? || object['maximum_area'].nil? }

      # Skip objects whose minimum area is below or maximum area is above area
      matching_objects = matching_objects.reject { |object| area.to_f <= object['minimum_area'].to_f || area.to_f > object['maximum_area'].to_f }
    end

    # If area was specified, narrow down the matching objects
    unless num_floors.nil?
      # Skip objects that don't have fields for minimum_floors and maximum_floors
      matching_objects = matching_objects.reject { |object| !object.key?('minimum_floors') || !object.key?('maximum_floors') }

      # Skip objects that don't have values specified for minimum_floors and maximum_floors
      matching_objects = matching_objects.reject { |object| object['minimum_floors'].nil? || object['maximum_floors'].nil? }

      # Skip objects whose minimum floors is below or maximum floors is above num_floors
      matching_objects = matching_objects.reject { |object| num_floors.to_f < object['minimum_floors'].to_f || num_floors.to_f > object['maximum_floors'].to_f }
    end

    # Check the number of matching objects found
    if matching_objects.empty?
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Model', "Find objects search criteria returned no results. Search criteria: #{search_criteria}. Called from #{caller(0)[1]}.")
    end

    return matching_objects
  end

  # Method to search through a hash for an object that meets the desired search criteria, as passed via a hash.
  # If capacity is supplied, the object will only be returned if the specified capacity is between the minimum_capacity and maximum_capacity values.
  #
  # @param hash_of_objects [Hash] hash of objects to search through
  # @param search_criteria [Hash] hash of search criteria
  # @param capacity [Double] capacity of the object in question.  If capacity is supplied,
  #   the objects will only be returned if the specified capacity is between the minimum_capacity and maximum_capacity values.
  # @param date [<OpenStudio::Date>] date of the object in question.  If date is supplied,
  #   the objects will only be returned if the specified date is between the start_date and end_date.
  # @param area [Double] area of the object in question.  If area is supplied,
  #   the objects will only be returned if the specified area is between the minimum_area and maximum_area values.
  # @param num_floors [Double] capacity of the object in question.  If num_floors is supplied,
  #   the objects will only be returned if the specified num_floors is between the minimum_floors and maximum_floors values.
  # @return [Hash] Return the first matching object hash if successful, nil if not.
  # @example Find the motor that meets these size criteria
  #   search_criteria = {
  #   'template' => template,
  #   'number_of_poles' => 4.0,
  #   'type' => 'Enclosed',
  #   }
  #   motor_properties = self.model.find_object(motors, search_criteria, capacity: 2.5)
  def model_find_object(hash_of_objects, search_criteria, capacity = nil, date = nil, area = nil, num_floors = nil, fan_motor_bhp = nil, volume = nil, capacity_per_volume = nil)
    matching_objects = model_find_objects(hash_of_objects, search_criteria, capacity, date, area, num_floors, fan_motor_bhp, volume, capacity_per_volume)

    # Check the number of matching objects found
    if matching_objects.empty?
      desired_object = nil
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Model', "Find object search criteria returned no results. Search criteria: #{search_criteria}. Called from #{caller(0)[1]}")
    elsif matching_objects.size == 1
      desired_object = matching_objects[0]
    else
      desired_object = matching_objects[0]
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Find object search criteria returned #{matching_objects.size} results, the first one will be returned. Called from #{caller(0)[1]}. \n Search criteria: \n #{search_criteria}, capacity = #{capacity} \n  All results: \n #{matching_objects.join("\n")}")
    end

    return desired_object
  end

  # Method to search through a hash for the objects that meets the desired search criteria, as passed via a hash.
  # Returns an Array (empty if nothing found) of matching objects.
  #
  # @param table_name [Hash] name of table in standards database.
  # @param search_criteria [Hash] hash of search criteria
  # @param capacity [Double] capacity of the object in question.  If capacity is supplied,
  #   the objects will only be returned if the specified capacity is between the minimum_capacity and maximum_capacity values.
  # @param date [<OpenStudio::Date>] date of the object in question.  If date is supplied,
  #   the objects will only be returned if the specified date is between the start_date and end_date.
  # @param area [Double] area of the object in question.  If area is supplied,
  #   the objects will only be returned if the specified area is between the minimum_area and maximum_area values.
  # @param num_floors [Double] capacity of the object in question.  If num_floors is supplied,
  #   the objects will only be returned if the specified num_floors is between the minimum_floors and maximum_floors values.
  # @return [Array] returns an array of hashes, one hash per object.  Array is empty if no results.
  # @example Find all the schedule rules that match the name
  #   rules = model_find_objects(standards_data['schedules'], 'name' => schedule_name)
  #   if rules.empty?
  #     OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', "Cannot find data for schedule: #{schedule_name}, will not be created.")
  #     return false
  #   end
  def standards_lookup_table_many(table_name:, search_criteria: {}, capacity: nil, date: nil, area: nil, num_floors: nil)
    desired_object = nil
    search_criteria_matching_objects = []
    matching_objects = []
    hash_of_objects = @standards_data[table_name]

    # needed for NRCan data structure compatibility. We keep all tables in a 'tables' hash in @standards_data and the table
    # itself is in the 'table' hash index.
    if hash_of_objects.nil?
      # Format of @standards_data is not NRCan-style and table simply doesn't exist.
      return matching_objects if @standards_data['tables'].nil?

      table = @standards_data['tables'][table_name]['table']
      hash_of_objects = table
    end

    # Compare each of the objects against the search criteria
    hash_of_objects.each do |object|
      meets_all_search_criteria = true
      search_criteria.each do |key, value|
        # Don't check non-existent search criteria
        next unless object.key?(key)

        # Stop as soon as one of the search criteria is not met
        # 'Any' is a special key that matches anything
        unless object[key] == value || object[key] == 'Any'
          meets_all_search_criteria = false
          break
        end
      end
      # Skip objects that don't meet all search criteria
      next unless meets_all_search_criteria

      # If made it here, object matches all search criteria
      matching_objects << object
    end

    # If capacity was specified, narrow down the matching objects
    unless capacity.nil?
      # Skip objects that don't have fields for minimum_capacity and maximum_capacity
      matching_objects = matching_objects.reject { |object| !object.key?('minimum_capacity') || !object.key?('maximum_capacity') }

      # Skip objects that don't have values specified for minimum_capacity and maximum_capacity
      matching_objects = matching_objects.reject { |object| object['minimum_capacity'].nil? || object['maximum_capacity'].nil? }

      # Convert to a float in case not already
      capacity = capacity.to_f

      # Skip objects whose the minimum capacity is below or maximum capacity above the specified capacity
      matching_capacity_objects = matching_objects.reject { |object| capacity <= object['minimum_capacity'].to_f || capacity > object['maximum_capacity'].to_f }

      # If no object was found, round the capacity down in case the number fell between the limits in the json file.
      if matching_capacity_objects.empty?
        capacity *= 0.99
        search_criteria_matching_objects.each do |object|
          # Skip objects that don't have fields for minimum_capacity and maximum_capacity
          next if !object.key?('minimum_capacity') || !object.key?('maximum_capacity')
          # Skip objects that don't have values specified for minimum_capacity and maximum_capacity
          next if object['minimum_capacity'].nil? || object['maximum_capacity'].nil?
          # Skip objects whose the minimum capacity is below the specified capacity
          next if capacity <= object['minimum_capacity'].to_f
          # Skip objects whose max
          next if capacity > object['maximum_capacity'].to_f

          # Found a matching object
          matching_objects << object
        end
      end
      # If date was specified, narrow down the matching objects
      unless date.nil?
        date_matching_objects = []
        matching_objects.each do |object|
          # Skip objects that don't have fields for minimum_capacity and maximum_capacity
          next if !object.key?('start_date') || !object.key?('end_date')
          # Skip objects whose the start date is earlier than the specified date
          next if date <= Date.parse(object['start_date'])
          # Skip objects whose end date is beyond the specified date
          next if date > Date.parse(object['end_date'])

          # Found a matching object
          date_matching_objects << object
        end
        matching_objects = date_matching_objects
      end
    end

    # If area was specified, narrow down the matching objects
    unless area.nil?
      # Skip objects that don't have fields for minimum_area and maximum_area
      matching_objects = matching_objects.reject { |object| !object.key?('minimum_area') || !object.key?('maximum_area') }

      # Skip objects that don't have values specified for minimum_area and maximum_area
      matching_objects = matching_objects.reject { |object| object['minimum_area'].nil? || object['maximum_area'].nil? }

      # Skip objects whose minimum area is below or maximum area is above area
      matching_objects = matching_objects.reject { |object| area.to_f <= object['minimum_area'].to_f || area.to_f > object['maximum_area'].to_f }
    end

    # If area was specified, narrow down the matching objects
    unless num_floors.nil?
      # Skip objects that don't have fields for minimum_floors and maximum_floors
      matching_objects = matching_objects.reject { |object| !object.key?('minimum_floors') || !object.key?('maximum_floors') }

      # Skip objects that don't have values specified for minimum_floors and maximum_floors
      matching_objects = matching_objects.reject { |object| object['minimum_floors'].nil? || object['maximum_floors'].nil? }

      # Skip objects whose minimum floors is below or maximum floors is above num_floors
      matching_objects = matching_objects.reject { |object| num_floors.to_f < object['minimum_floors'].to_f || num_floors.to_f > object['maximum_floors'].to_f }
    end

    # Check the number of matching objects found
    if matching_objects.empty?
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Model', "Find objects search criteria returned no results. Search criteria: #{search_criteria}. Called from #{caller(0)[1]}.")
    end

    return matching_objects
  end

  # Method to search through a hash for an object that meets the desired search criteria, as passed via a hash.
  # If capacity is supplied, the object will only be returned if the specified capacity is between the minimum_capacity and maximum_capacity values.
  #
  # @param table_name [String] name of table
  # @param search_criteria [Hash] hash of search criteria
  # @param capacity [Double] capacity of the object in question.  If capacity is supplied,
  #   the objects will only be returned if the specified capacity is between the minimum_capacity and maximum_capacity values.
  # @param date [<OpenStudio::Date>] date of the object in question.  If date is supplied,
  #   the objects will only be returned if the specified date is between the start_date and end_date.
  # @return [Hash] Return the first matching object hash if successful, nil if not.
  # @example Find the motor that meets these size criteria
  #   search_criteria = {
  #   'template' => template,
  #   'number_of_poles' => 4.0,
  #   'type' => 'Enclosed',
  #   }
  #   motor_properties = self.model.find_object(motors, search_criteria, 2.5)
  def standards_lookup_table_first(table_name:, search_criteria: {}, capacity: nil, date: nil)
    # run the many version of the look up code...DRY.
    matching_objects = standards_lookup_table_many(table_name: table_name,
                                                   search_criteria: search_criteria,
                                                   capacity: capacity,
                                                   date: date)

    # Check the number of matching objects found
    if matching_objects.empty?
      desired_object = nil
      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Model', "Find object search criteria returned no results. Search criteria: #{search_criteria}. Called from #{caller(0)[1]}")
    elsif matching_objects.size == 1
      desired_object = matching_objects[0]
    else
      desired_object = matching_objects[0]
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Find object search criteria returned #{matching_objects.size} results, the first one will be returned. Called from #{caller(0)[1]}. \n Search criteria: \n #{search_criteria}, capacity = #{capacity} \n  All results: \n#{matching_objects.join("\n")}")
    end

    return desired_object
  end

  # Create a schedule from the openstudio standards dataset and add it to the model.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param schedule_name [String} name of the schedule
  # @return [ScheduleRuleset] the resulting schedule ruleset
  # @todo make return an OptionalScheduleRuleset
  def model_add_schedule(model, schedule_name)
    return nil if schedule_name.nil? || schedule_name == ''

    # First check model and return schedule if it already exists
    model.getSchedules.sort.each do |schedule|
      if schedule.name.get.to_s == schedule_name
        OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Model', "Already added schedule: #{schedule_name}")
        return schedule
      end
    end

    require 'date'

    # OpenStudio::logFree(OpenStudio::Info, 'openstudio.standards.Model', "Adding schedule: #{schedule_name}")

    # Find all the schedule rules that match the name
    rules = model_find_objects(standards_data['schedules'], 'name' => schedule_name)
    if rules.empty?
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', "Cannot find data for schedule: #{schedule_name}, will not be created.")
      return model.alwaysOnDiscreteSchedule
    end

    # Make a schedule ruleset
    sch_ruleset = OpenStudio::Model::ScheduleRuleset.new(model)
    sch_ruleset.setName(schedule_name.to_s)

    # Loop through the rules, making one for each row in the spreadsheet
    rules.each do |rule|
      day_types = rule['day_types']
      start_date = DateTime.parse(rule['start_date'])
      end_date = DateTime.parse(rule['end_date'])
      sch_type = rule['type']
      values = rule['values']

      # Day Type choices: Wkdy, Wknd, Mon, Tue, Wed, Thu, Fri, Sat, Sun, WntrDsn, SmrDsn, Hol
      # Default
      if day_types.include?('Default')
        day_sch = sch_ruleset.defaultDaySchedule
        day_sch.setName("#{schedule_name} Default")
        model_add_vals_to_sch(model, day_sch, sch_type, values)
        if model.version < OpenStudio::VersionString.new('3.8.0')
          day_sch.setInterpolatetoTimestep(false)
        else
          day_sch.setInterpolatetoTimestep('No')
        end
      end

      # Winter Design Day. The setter clones what it is handed, so a day schedule built
      # here and handed over would be left in the model with no parent, reaching the IDF
      # with no type limits. As in create_simple_schedule: set from the ruleset's own
      # getter, take the clone back, clear it, and fill that.
      if day_types.include?('WntrDsn')
        sch_ruleset.setWinterDesignDaySchedule(sch_ruleset.winterDesignDaySchedule)
        day_sch = sch_ruleset.winterDesignDaySchedule
        day_sch.clearValues
        day_sch.setName("#{schedule_name} Winter Design Day")
        model_add_vals_to_sch(model, day_sch, sch_type, values)
        if model.version < OpenStudio::VersionString.new('3.8.0')
          day_sch.setInterpolatetoTimestep(false)
        else
          day_sch.setInterpolatetoTimestep('No')
        end
      end

      # Summer Design Day
      if day_types.include?('SmrDsn')
        sch_ruleset.setSummerDesignDaySchedule(sch_ruleset.summerDesignDaySchedule)
        day_sch = sch_ruleset.summerDesignDaySchedule
        day_sch.clearValues
        day_sch.setName("#{schedule_name} Summer Design Day")
        model_add_vals_to_sch(model, day_sch, sch_type, values)
        if model.version < OpenStudio::VersionString.new('3.8.0')
          day_sch.setInterpolatetoTimestep(false)
        else
          day_sch.setInterpolatetoTimestep('No')
        end
      end

      # Other days (weekdays, weekends, etc)
      if day_types.include?('Wknd') ||
         day_types.include?('Wkdy') ||
         day_types.include?('Sat') ||
         day_types.include?('Sun') ||
         day_types.include?('Mon') ||
         day_types.include?('Tue') ||
         day_types.include?('Wed') ||
         day_types.include?('Thu') ||
         day_types.include?('Fri')

        # Make the Rule
        sch_rule = OpenStudio::Model::ScheduleRule.new(sch_ruleset)
        day_sch = sch_rule.daySchedule
        day_sch.setName("#{schedule_name} #{day_types} Day")
        model_add_vals_to_sch(model, day_sch, sch_type, values)
        if model.version < OpenStudio::VersionString.new('3.8.0')
          day_sch.setInterpolatetoTimestep(false)
        else
          day_sch.setInterpolatetoTimestep('No')
        end

        # Set the dates when the rule applies
        sch_rule.setStartDate(OpenStudio::Date.new(OpenStudio::MonthOfYear.new(start_date.month.to_i), start_date.day.to_i))
        sch_rule.setEndDate(OpenStudio::Date.new(OpenStudio::MonthOfYear.new(end_date.month.to_i), end_date.day.to_i))

        # Set the days when the rule applies
        # Weekends
        if day_types.include?('Wknd')
          sch_rule.setApplySaturday(true)
          sch_rule.setApplySunday(true)
        end
        # Weekdays
        if day_types.include?('Wkdy')
          sch_rule.setApplyMonday(true)
          sch_rule.setApplyTuesday(true)
          sch_rule.setApplyWednesday(true)
          sch_rule.setApplyThursday(true)
          sch_rule.setApplyFriday(true)
        end
        # Individual Days
        sch_rule.setApplyMonday(true) if day_types.include?('Mon')
        sch_rule.setApplyTuesday(true) if day_types.include?('Tue')
        sch_rule.setApplyWednesday(true) if day_types.include?('Wed')
        sch_rule.setApplyThursday(true) if day_types.include?('Thu')
        sch_rule.setApplyFriday(true) if day_types.include?('Fri')
        sch_rule.setApplySaturday(true) if day_types.include?('Sat')
        sch_rule.setApplySunday(true) if day_types.include?('Sun')
      end
    end
    return sch_ruleset
  end

  # Create a material from the openstudio standards dataset.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param material_name [String] name of the material
  # @return [OpenStudio::Model::Material] material object
  def model_add_material(model, material_name)
    # First check model and return material if it already exists
    model.getMaterials.sort.each do |material|
      if material.name.get.to_s == material_name
        OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Model', "Already added material: #{material_name}")
        return material
      end
    end

    # Get the object data
    # For Simple Glazing materials:
    # Attempt to get properties from the name of the material
    material_type = nil
    if material_name.downcase.include?('simple glazing')
      material_type = 'SimpleGlazing'
      u_factor = nil
      shgc = nil
      vt = nil
      material_name.split.each_with_index do |item, i|
        prop_value = material_name.split[i + 1].to_f
        case item
        when 'U'
          unless u_factor.nil?
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Multiple U-Factor values have been identified for #{material_name}: previous = #{u_factor}, new = #{prop_value}. Please check the material name. New U-Factor will be used.")
          end
          u_factor = prop_value
        when 'SHGC'
          unless shgc.nil?
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Multiple SHGC values have been identified for #{material_name}: previous = #{shgc}, new = #{prop_value}. Please check the material name. New SHGC will be used.")
          end
          shgc = prop_value
        when 'VT'
          unless vt.nil?
            OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Multiple VT values have been identified for #{material_name}: previous = #{vt}, new = #{prop_value}. Please check the material name. New SHGC will be used.")
          end
          vt = prop_value
        end
      end
      if u_factor.nil? && shgc.nil? && vt.nil?
        material_type = nil
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Properties of the simple glazing material named #{material_name} could not be identified from its name.")
      else
        if u_factor.nil?
          u_factor = 1.23
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Cannot find the U-Factor for the simple glazing material named #{material_name}, a default value of 1.23 is used.")
        end
        if shgc.nil?
          shgc = 0.61
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Cannot find the SHGC for the simple glazing material named #{material_name}, a default value of 0.61 is used.")
        end
        if vt.nil?
          vt = 0.81
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Cannot find the VT for the simple glazing material named #{material_name}, a default value of 0.81 is used.")
        end
      end
    end
    # If no properties could be found or the material
    # is not of the simple glazing type, search the database
    if material_type.nil?
      data = model_find_object(standards_data['materials'], 'name' => material_name)
      unless data
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Cannot find data for material: #{material_name}, will not be created.")
        return OpenStudio::Model::OptionalMaterial.new
      end
      material_type = data['material_type']
    end

    material = nil
    case material_type
    when 'StandardOpaqueMaterial'
      material = OpenStudio::Model::StandardOpaqueMaterial.new(model)
      material.setName(material_name)

      material.setRoughness(data['roughness'].to_s)
      material.setThickness(OpenStudio.convert(data['thickness'].to_f, 'in', 'm').get)
      material.setThermalConductivity(OpenStudio.convert(data['conductivity'].to_f, 'Btu*in/hr*ft^2*R', 'W/m*K').get)
      material.setDensity(OpenStudio.convert(data['density'].to_f, 'lb/ft^3', 'kg/m^3').get)
      material.setSpecificHeat(OpenStudio.convert(data['specific_heat'].to_f, 'Btu/lb*R', 'J/kg*K').get)
      material.setThermalAbsorptance(data['thermal_absorptance'].to_f)
      material.setSolarAbsorptance(data['solar_absorptance'].to_f)
      material.setVisibleAbsorptance(data['visible_absorptance'].to_f)

    when 'MasslessOpaqueMaterial'
      material = OpenStudio::Model::MasslessOpaqueMaterial.new(model)
      material.setName(material_name)
      material.setThermalResistance(OpenStudio.convert(data['resistance'].to_f, 'hr*ft^2*R/Btu', 'm^2*K/W').get)
      material.setThermalConductivity(OpenStudio.convert(data['conductivity'].to_f, 'Btu*in/hr*ft^2*R', 'W/m*K').get)
      material.setThermalAbsorptance(data['thermal_absorptance'].to_f)
      material.setSolarAbsorptance(data['solar_absorptance'].to_f)
      material.setVisibleAbsorptance(data['visible_absorptance'].to_f)

    when 'AirGap'
      material = OpenStudio::Model::AirGap.new(model)
      material.setName(material_name)

      material.setThermalResistance(OpenStudio.convert(data['resistance'].to_f, 'hr*ft^2*R/Btu*in', 'm*K/W').get)

    when 'Gas'
      material = OpenStudio::Model::Gas.new(model)
      material.setName(material_name)

      material.setThickness(OpenStudio.convert(data['thickness'].to_f, 'in', 'm').get)
      material.setGasType(data['gas_type'].to_s)

    when 'SimpleGlazing'
      material = OpenStudio::Model::SimpleGlazing.new(model)
      material.setName(material_name)

      material.setUFactor(OpenStudio.convert(u_factor.to_f, 'Btu/hr*ft^2*R', 'W/m^2*K').get)
      material.setSolarHeatGainCoefficient(shgc.to_f)
      material.setVisibleTransmittance(vt.to_f)

    when 'StandardGlazing'
      material = OpenStudio::Model::StandardGlazing.new(model)
      material.setName(material_name)

      material.setOpticalDataType(data['optical_data_type'].to_s)
      material.setThickness(OpenStudio.convert(data['thickness'].to_f, 'in', 'm').get)
      material.setSolarTransmittanceatNormalIncidence(data['solar_transmittance_at_normal_incidence'].to_f)
      material.setFrontSideSolarReflectanceatNormalIncidence(data['front_side_solar_reflectance_at_normal_incidence'].to_f)
      material.setBackSideSolarReflectanceatNormalIncidence(data['back_side_solar_reflectance_at_normal_incidence'].to_f)
      material.setVisibleTransmittanceatNormalIncidence(data['visible_transmittance_at_normal_incidence'].to_f)
      material.setFrontSideVisibleReflectanceatNormalIncidence(data['front_side_visible_reflectance_at_normal_incidence'].to_f)
      material.setBackSideVisibleReflectanceatNormalIncidence(data['back_side_visible_reflectance_at_normal_incidence'].to_f)
      material.setInfraredTransmittanceatNormalIncidence(data['infrared_transmittance_at_normal_incidence'].to_f)
      material.setFrontSideInfraredHemisphericalEmissivity(data['front_side_infrared_hemispherical_emissivity'].to_f)
      material.setBackSideInfraredHemisphericalEmissivity(data['back_side_infrared_hemispherical_emissivity'].to_f)
      material.setThermalConductivity(OpenStudio.convert(data['conductivity'].to_f, 'Btu*in/hr*ft^2*R', 'W/m*K').get)
      material.setDirtCorrectionFactorforSolarandVisibleTransmittance(data['dirt_correction_factor_for_solar_and_visible_transmittance'].to_f)
      if /true/i =~ data['solar_diffusing'].to_s
        material.setSolarDiffusing(true)
      else
        material.setSolarDiffusing(false)
      end

    else
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', "Unknown material type #{material_type}, cannot add material called #{material_name}.")
      exit
    end

    return material
  end

  # Create a construction from the openstudio standards dataset.
  # If construction_props are specified, modifies the insulation layer accordingly.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param construction_name [String] name of the construction
  # @param construction_props [Hash] hash of construction properties
  # @return [OpenStudio::Model::Construction] construction object
  # @todo make return an OptionalConstruction
  def model_add_construction(model, construction_name, construction_props = nil, surface = nil)
    intended_surface_type = construction_props&.[]('intended_surface_type') || ''

    # First check model and return construction if it already exists
    model.getConstructions.sort.each do |construction|
      if construction.name.get.to_s == construction_name
        OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Model', "Already added construction: #{construction_name}")
        valid = true
        if !surface.nil?
          if intended_surface_type == 'GroundContactFloor' && construction.iddObjectType.valueName != 'OS_Construction_FfactorGroundFloor'
            valid = false
          elsif intended_surface_type == 'GroundContactWall' && construction.iddObjectType.valueName != 'OS_Construction_CfactorUndergroundWall'
            valid = false
          end
        end
        if valid
          return construction
        end
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Already added construction: '#{construction_name}' but its type '#{construction.iddObjectType.valueName}' is not valid for the intended surface type '#{intended_surface_type}'. A new construction will be created.")
      end
    end

    OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Model', "Adding construction: #{construction_name}")

    # Get the object data
    data = model_find_object(standards_data['constructions'], 'name' => construction_name)

    unless data
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Cannot find data for construction: #{construction_name}, will not be created.")
      return OpenStudio::Model::OptionalConstruction.new
    end

    intended_surface_type = data["intended_surface_type"]
    intended_surface_type ||= ''

    # Make a new construction and set the standards details
    is_layered_construction = true

    if intended_surface_type == 'GroundContactFloor' && !surface.nil?
      if construction_props
        construction = OpenStudio::Model::FFactorGroundFloorConstruction.new(model)
        is_layered_construction = false
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Construction properties not specified for '#{construction_name}', cannot create F-Factor Ground Floor Construction.  A regular construction will be created instead, and Surface '#{surface.name}' will be set to use the 'Ground' outside boundary condition (previously '#{surface.outsideBoundaryCondition}').")
        surface.setOutsideBoundaryCondition('Ground')
      end
    elsif intended_surface_type == 'GroundContactWall' && !surface.nil?
      if construction_props
        construction = OpenStudio::Model::CFactorUndergroundWallConstruction.new(model)
        is_layered_construction = false
      else
        OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Construction properties not specified for '#{construction_name}', cannot create C-Factor Underground Wall Construction.  A regular construction will be created instead, and Surface '#{surface.name}' will be set to use the 'Ground' outside boundary condition (previously '#{surface.outsideBoundaryCondition}').")
        surface.setOutsideBoundaryCondition('Ground')
      end
    end

    if is_layered_construction
      construction = OpenStudio::Model::Construction.new(model)
      # Add the material layers to the construction
      layers = OpenStudio::Model::MaterialVector.new
      data['materials'].each do |material_name|
        material = model_add_material(model, material_name)
        if material
          layers << material
        end
      end
      construction.setLayers(layers)
    end
    construction.setName(construction_name)
    standards_info = construction.standardsInformation

    standards_info.setIntendedSurfaceType(intended_surface_type)

    standards_construction_type = data['standards_construction_type']
    standards_construction_type ||= ''
    standards_info.setStandardsConstructionType(standards_construction_type)

    # @todo could put construction rendering color in the spreadsheet

    # Modify the R value of the insulation to hit the specified U-value, C-Factor, or F-Factor.
    # Doesn't currently operate on glazing constructions
    if construction_props
      # Determine the target U-value, C-factor, and F-factor
      target_u_value_ip = construction_props['assembly_maximum_u_value']
      target_f_factor_ip = construction_props['assembly_maximum_f_factor']
      target_c_factor_ip = construction_props['assembly_maximum_c_factor']
      target_shgc = construction_props['assembly_maximum_solar_heat_gain_coefficient']
      u_includes_int_film = construction_props['u_value_includes_interior_film_coefficient']
      u_includes_ext_film = construction_props['u_value_includes_exterior_film_coefficient']

      OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Model', "#{data['intended_surface_type']} u_val #{target_u_value_ip} f_fac #{target_f_factor_ip} c_fac #{target_c_factor_ip}")

      if target_u_value_ip

        # Handle Opaque and Fenestration Constructions differently
        # if construction.isFenestration && OpenstudioStandards::Constructions.construction_simple_glazing?(construction)
        if construction.isFenestration
          if OpenstudioStandards::Constructions.construction_simple_glazing?(construction)
            # Set the U-Value and SHGC
            OpenstudioStandards::Constructions.construction_set_glazing_u_value(construction, target_u_value_ip.to_f,
                                                                                target_includes_interior_film_coefficients: u_includes_int_film,
                                                                                target_includes_exterior_film_coefficients: u_includes_ext_film)
            simple_glazing = construction.layers.first.to_SimpleGlazing
            unless simple_glazing.is_initialized && !target_shgc.nil?
              simple_glazing.get.setSolarHeatGainCoefficient(target_shgc.to_f)
            end
          else # if !data['intended_surface_type'] == 'ExteriorWindow' && !data['intended_surface_type'] == 'Skylight'
            # Set the U-Value
            OpenstudioStandards::Constructions.construction_set_u_value(construction, target_u_value_ip.to_f,
                                                                        insulation_layer_name: data['insulation_layer'],
                                                                        intended_surface_type: data['intended_surface_type'],
                                                                        target_includes_interior_film_coefficients: u_includes_int_film,
                                                                        target_includes_exterior_film_coefficients: u_includes_ext_film)
            # else
            # OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Not modifying U-value for #{data['intended_surface_type']} u_val #{target_u_value_ip} f_fac #{target_f_factor_ip} c_fac #{target_c_factor_ip}")
          end
        else
          # Set the U-Value
          OpenstudioStandards::Constructions.construction_set_u_value(construction, target_u_value_ip.to_f,
                                                                      insulation_layer_name: data['insulation_layer'],
                                                                      intended_surface_type: data['intended_surface_type'],
                                                                      target_includes_interior_film_coefficients: u_includes_int_film,
                                                                      target_includes_exterior_film_coefficients: u_includes_ext_film)
          # else
          # OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Not modifying U-value for #{data['intended_surface_type']} u_val #{target_u_value_ip} f_fac #{target_f_factor_ip} c_fac #{target_c_factor_ip}")
        end

      elsif target_f_factor_ip && data['intended_surface_type'] == 'GroundContactFloor'
        # F-factor objects are unique to each surface, so a surface needs to be passed
        # If not surface is passed, use the older approach to model ground contact floors
        if surface.nil?
          # Set the F-Factor (only applies to slabs on grade)
          # @todo figure out what the prototype buildings did about ground heat transfer
          # OpenstudioStandards::Constructions.construction_set_slab_f_factor(construction, target_f_factor_ip.to_f, insulation_layer_name: data['insulation_layer'])
          OpenstudioStandards::Constructions.construction_set_u_value(construction, 0.0,
                                                                      insulation_layer_name: data['insulation_layer'],
                                                                      intended_surface_type: data['intended_surface_type'],
                                                                      target_includes_interior_film_coefficients: u_includes_int_film,
                                                                      target_includes_exterior_film_coefficients: u_includes_ext_film)
        else
          OpenstudioStandards::Constructions.construction_set_surface_slab_f_factor(construction, target_f_factor_ip, surface)
        end
      elsif target_c_factor_ip && (data['intended_surface_type'] == 'GroundContactWall' || data['intended_surface_type'] == 'GroundContactRoof')
        # C-factor objects are unique to each surface, so a surface needs to be passed
        # If not surface is passed, use the older approach to model ground contact walls
        if surface.nil?
          # Set the C-Factor (only applies to underground walls)
          # @todo figure out what the prototype buildings did about ground heat transfer
          # OpenstudioStandards::Constructions.construction_set_underground_wall_c_factor(construction, target_c_factor_ip.to_f, insulation_layer_name: data['insulation_layer'])
          OpenstudioStandards::Constructions.construction_set_u_value(construction, 0.0,
                                                                      insulation_layer_name: data['insulation_layer'],
                                                                      intended_surface_type: data['intended_surface_type'],
                                                                      target_includes_interior_film_coefficients: u_includes_int_film,
                                                                      target_includes_exterior_film_coefficients: u_includes_ext_film)
        else
          OpenstudioStandards::Constructions.construction_set_surface_underground_wall_c_factor(construction, target_c_factor_ip, surface)
        end
      end

      # If the construction is fenestration,
      # also set the frame type for use in future lookups
      if construction.isFenestration
        case standards_construction_type
        when 'Metal framing (all other)'
          standards_info.setFenestrationFrameType('Metal Framing')
        when 'Nonmetal framing (all)'
          standards_info.setFenestrationFrameType('Non-Metal Framing')
        end
      end

      # If the construction has a skylight framing material specified,
      # get the skylight frame material properties and add frame to
      # all skylights in the model.
      if data['skylight_framing']
        # Get the skylight framing material
        framing_name = data['skylight_framing']
        frame_data = model_find_object(standards_data['materials'], 'name' => framing_name)
        if frame_data
          frame_width_in = frame_data['frame_width'].to_f
          frame_with_m = OpenStudio.convert(frame_width_in, 'in', 'm').get
          frame_resistance_ip = frame_data['resistance'].to_f
          frame_resistance_si = OpenStudio.convert(frame_resistance_ip, 'hr*ft^2*R/Btu', 'm^2*K/W').get
          frame_conductance_si = 1.0 / frame_resistance_si
          frame = OpenStudio::Model::WindowPropertyFrameAndDivider.new(model)
          frame.setName("Skylight frame R-#{frame_resistance_ip.round(2)} #{frame_width_in.round(1)} in. wide")
          frame.setFrameWidth(frame_with_m)
          frame.setFrameConductance(frame_conductance_si)
          skylights_frame_added = 0
          model.getSubSurfaces.each do |sub_surface|
            next unless sub_surface.outsideBoundaryCondition == 'Outdoors' && sub_surface.subSurfaceType == 'Skylight'

            if model.version < OpenStudio::VersionString.new('3.1.0')
              # window frame setting before https://github.com/NREL/OpenStudio/issues/2895 was fixed
              sub_surface.setString(8, frame.name.get.to_s)
              skylights_frame_added += 1
            else
              if sub_surface.allowWindowPropertyFrameAndDivider
                sub_surface.setWindowPropertyFrameAndDivider(frame)
                skylights_frame_added += 1
              else
                OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "For #{sub_surface.name}: cannot add a frame to this skylight.")
              end
            end
          end
          OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Adding #{frame.name} to #{skylights_frame_added} skylights.") if skylights_frame_added > 0
        else
          OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Cannot find skylight framing data for: #{framing_name}, will not be created.")
          return false
          # @todo change to return empty optional material
        end
      end

    end
    #     # Check if the construction with the modified name was already in the model.
    #     # If it was, delete this new construction and return the copy already in the model.
    #     m = construction.name.get.to_s.match(/\s(\d+)/)
    #     if m
    #       revised_cons_name = construction.name.get.to_s.gsub(/\s\d+/,'')
    #       model.getConstructions.sort.each do |exist_construction|
    #         if exist_construction.name.get.to_s == revised_cons_name
    #           OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Model', "Already added construction: #{construction_name}")
    #           # Remove the recently added construction
    #           lyrs = construction.layers
    #           # Erase the layers in the construction
    #           construction.setLayers([])
    #           # Delete unused materials
    #           lyrs.uniq.each do |lyr|
    #             if lyr.directUseCount.zero?
    #               OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', "Removing Material: #{lyr.name}")
    #               lyr.remove
    #             end
    #           end
    #           construction.remove # Remove the construction
    #           return exist_construction
    #         end
    #       end
    #     end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Adding construction #{construction.name}.")

    return construction
  end

  # Helper method to find a particular construction and add it to the model after modifying the insulation value if necessary.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param climate_zone_set [String] climate zone set
  # @param intended_surface_type [String] intended surface type
  # @param standards_construction_type [String] standards construction type
  # @param building_category [String] building category
  # @param wwr_building_type [String] building type used to determine WWR for the PRM baseline model
  # @param wwr_info [Hash] @Todo - check what this is used for
  # @param surface [OpenStudio::Model::Surface] OpenStudio surface object, only used for surface specific construction, e.g F/C-factor constructions
  # @return [OpenStudio::Model::Construction] construction object
  def model_find_and_add_construction(model, climate_zone_set, intended_surface_type, standards_construction_type, building_category, wwr_building_type: nil, wwr_info: {}, surface: nil)
    # Get the construction properties,
    # which specifies properties by construction category by climate zone set.
    # AKA the info in Tables 5.5-1-5.5-8

    search_criteria = { 'template' => template,
                        'climate_zone_set' => climate_zone_set,
                        'intended_surface_type' => intended_surface_type,
                        'standards_construction_type' => standards_construction_type,
                        'building_category' => building_category }

    # Check if WWR criteria is needed for the construction search
    wwr_parameter = { 'intended_surface_type' => intended_surface_type }
    if wwr_building_type
      wwr_parameter['wwr_building_type'] = wwr_building_type
      wwr_parameter['wwr_info'] = wwr_info
    end
    wwr_range = model_get_percent_of_surface_range(model, wwr_parameter)

    if !wwr_range['minimum_percent_of_surface'].nil? && !wwr_range['maximum_percent_of_surface'].nil?
      search_criteria['minimum_percent_of_surface'] = wwr_range['minimum_percent_of_surface']
      search_criteria['maximum_percent_of_surface'] = wwr_range['maximum_percent_of_surface']
    end

    # First search
    props = model_find_object(standards_data['construction_properties'], search_criteria)

    if !props
      # Second search: In case need to use climate zone (e.g: 3) instead of sub-climate zone (e.g: 3A) for search
      climate_zone = climate_zone_set[0..-2]
      search_criteria['climate_zone_set'] = climate_zone
      props = model_find_object(standards_data['construction_properties'], search_criteria)
    end

    if !props
      # Third search for legacy energy codes (2016 or earlier), which does not have standards_construction_type
      search_criteria.delete('standards_construction_type')
      props = model_find_object(standards_data['construction_properties'], search_criteria)
    end

    if !props
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', "Could not find construction properties for: #{template}-#{climate_zone_set}-#{intended_surface_type}-#{standards_construction_type}-#{building_category}.")
      # Return an empty construction
      construction = OpenStudio::Model::Construction.new(model)
      construction.setName('Could not find construction properties set to Adiabatic ')
      almost_adiabatic = OpenStudio::Model::MasslessOpaqueMaterial.new(model, 'Smooth', 500)
      construction.insertLayer(0, almost_adiabatic)
      return construction
    end

    # Make sure that a construction is specified
    if props['construction'].nil?
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', "No typical construction is specified for construction properties of: #{template}-#{climate_zone_set}-#{intended_surface_type}-#{standards_construction_type}-#{building_category}.  Make sure it is entered in the spreadsheet.")
      # Return an empty construction
      construction = OpenStudio::Model::Construction.new(model)
      construction.setName('No typical construction was specified')
      return construction
    end

    # Add the construction, modifying properties as necessary
    construction = model_add_construction(model, props['construction'], props, surface)

    return construction
  end

  # Create a construction set from the openstudio standards dataset.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @param building_type [String] the building type
  # @param spc_type [String] the space type
  # @param is_residential [Boolean] true if the building is residential
  # @return [OpenStudio::Model::OptionalDefaultConstructionSet] an optional default construction set
  def model_add_construction_set(model, climate_zone, building_type, spc_type, is_residential)
    construction_set = OpenStudio::Model::OptionalDefaultConstructionSet.new

    # Find the climate zone set that this climate zone falls into
    climate_zone_set = model_find_climate_zone_set(model, climate_zone)
    unless climate_zone_set
      return construction_set
    end

    # Get the object data
    data = model_find_object(standards_data['construction_sets'], 'template' => template, 'climate_zone_set' => climate_zone_set, 'building_type' => building_type, 'space_type' => spc_type, 'is_residential' => is_residential)
    unless data
      # Search again without the is_residential criteria in the case that this field is not specified for a standard
      data = model_find_object(standards_data['construction_sets'], 'template' => template, 'climate_zone_set' => climate_zone_set, 'building_type' => building_type, 'space_type' => spc_type)
      unless data
        # if nothing matches say that we could not find it
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "Construction set for template =#{template}, climate zone set =#{climate_zone_set}, building type = #{building_type}, space type = #{spc_type}, is residential = #{is_residential} was not found in standards_data['construction_sets']")
        return construction_set
      end
    end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Adding construction set: #{template}-#{climate_zone}-#{building_type}-#{spc_type}-is_residential#{is_residential}")

    name = model_make_name(model, climate_zone, building_type, spc_type)

    # Create a new construction set and name it
    construction_set = OpenStudio::Model::DefaultConstructionSet.new(model)
    construction_set.setName(name)

    # Exterior surfaces constructions
    exterior_surfaces = OpenStudio::Model::DefaultSurfaceConstructions.new(model)
    construction_set.setDefaultExteriorSurfaceConstructions(exterior_surfaces)
    # Special condition for attics, where the insulation is actually on the floor but the soffit is uninsulated
    if spc_type == 'Attic'
      exterior_surfaces.setFloorConstruction(model_add_construction(model, 'Typical Attic Soffit'))
    else
      if data['exterior_floor_standards_construction_type'] && data['exterior_floor_building_category']
        exterior_surfaces.setFloorConstruction(model_find_and_add_construction(model,
                                                                               climate_zone_set,
                                                                               'ExteriorFloor',
                                                                               data['exterior_floor_standards_construction_type'],
                                                                               data['exterior_floor_building_category']))
      end
    end
    if data['exterior_wall_standards_construction_type'] && data['exterior_wall_building_category']
      exterior_surfaces.setWallConstruction(model_find_and_add_construction(model,
                                                                            climate_zone_set,
                                                                            'ExteriorWall',
                                                                            data['exterior_wall_standards_construction_type'],
                                                                            data['exterior_wall_building_category']))
    end
    # Special condition for attics, where the insulation is actually on the floor and the roof itself is uninsulated
    if spc_type == 'Attic'
      if data['exterior_roof_standards_construction_type'] && data['exterior_roof_building_category']
        exterior_surfaces.setRoofCeilingConstruction(model_add_construction(model, 'Typical Uninsulated Wood Joist Attic Roof'))
      end
    else
      if data['exterior_roof_standards_construction_type'] && data['exterior_roof_building_category']
        exterior_surfaces.setRoofCeilingConstruction(model_find_and_add_construction(model,
                                                                                     climate_zone_set,
                                                                                     'ExteriorRoof',
                                                                                     data['exterior_roof_standards_construction_type'],
                                                                                     data['exterior_roof_building_category']))
      end
    end
    # Interior surfaces constructions
    interior_surfaces = OpenStudio::Model::DefaultSurfaceConstructions.new(model)
    construction_set.setDefaultInteriorSurfaceConstructions(interior_surfaces)
    construction_name = data['interior_floors']
    # Special condition for attics, where the insulation is actually on the floor and the roof itself is uninsulated
    if spc_type == 'Attic'
      if data['exterior_roof_standards_construction_type'] && data['exterior_roof_building_category']
        interior_surfaces.setFloorConstruction(model_find_and_add_construction(model,
                                                                               climate_zone_set,
                                                                               'ExteriorRoof',
                                                                               data['exterior_roof_standards_construction_type'],
                                                                               data['exterior_roof_building_category']))

      end
    else
      unless construction_name.nil?
        interior_surfaces.setFloorConstruction(model_add_construction(model, construction_name))
      end
    end
    construction_name = data['interior_walls']
    unless construction_name.nil?
      interior_surfaces.setWallConstruction(model_add_construction(model, construction_name))
    end
    construction_name = data['interior_ceilings']
    unless construction_name.nil?
      interior_surfaces.setRoofCeilingConstruction(model_add_construction(model, construction_name))
    end

    # Ground contact surfaces constructions
    ground_surfaces = OpenStudio::Model::DefaultSurfaceConstructions.new(model)
    construction_set.setDefaultGroundContactSurfaceConstructions(ground_surfaces)
    if data['ground_contact_floor_standards_construction_type'] && data['ground_contact_floor_building_category']
      ground_surfaces.setFloorConstruction(model_find_and_add_construction(model,
                                                                           climate_zone_set,
                                                                           'GroundContactFloor',
                                                                           data['ground_contact_floor_standards_construction_type'],
                                                                           data['ground_contact_floor_building_category']))
    end
    if data['ground_contact_wall_standards_construction_type'] && data['ground_contact_wall_building_category']
      ground_surfaces.setWallConstruction(model_find_and_add_construction(model,
                                                                          climate_zone_set,
                                                                          'GroundContactWall',
                                                                          data['ground_contact_wall_standards_construction_type'],
                                                                          data['ground_contact_wall_building_category']))
    end
    if data['ground_contact_ceiling_standards_construction_type'] && data['ground_contact_ceiling_building_category']
      ground_surfaces.setRoofCeilingConstruction(model_find_and_add_construction(model,
                                                                                 climate_zone_set,
                                                                                 'GroundContactRoof',
                                                                                 data['ground_contact_ceiling_standards_construction_type'],
                                                                                 data['ground_contact_ceiling_building_category']))

    end

    # Exterior sub surfaces constructions
    exterior_subsurfaces = OpenStudio::Model::DefaultSubSurfaceConstructions.new(model)
    construction_set.setDefaultExteriorSubSurfaceConstructions(exterior_subsurfaces)
    if data['exterior_fixed_window_standards_construction_type'] && data['exterior_fixed_window_building_category']
      exterior_subsurfaces.setFixedWindowConstruction(model_find_and_add_construction(model,
                                                                                      climate_zone_set,
                                                                                      'ExteriorWindow',
                                                                                      data['exterior_fixed_window_standards_construction_type'],
                                                                                      data['exterior_fixed_window_building_category']))
    end
    if data['exterior_operable_window_standards_construction_type'] && data['exterior_operable_window_building_category']
      exterior_subsurfaces.setOperableWindowConstruction(model_find_and_add_construction(model,
                                                                                         climate_zone_set,
                                                                                         'ExteriorWindow',
                                                                                         data['exterior_operable_window_standards_construction_type'],
                                                                                         data['exterior_operable_window_building_category']))
    end
    if data['exterior_door_standards_construction_type'] && data['exterior_door_building_category']
      exterior_subsurfaces.setDoorConstruction(model_find_and_add_construction(model,
                                                                               climate_zone_set,
                                                                               'ExteriorDoor',
                                                                               data['exterior_door_standards_construction_type'],
                                                                               data['exterior_door_building_category']))
    end
    if data['exterior_glass_door_standards_construction_type'] && data['exterior_glass_door_building_category']
      exterior_subsurfaces.setGlassDoorConstruction(model_find_and_add_construction(model,
                                                                                    climate_zone_set,
                                                                                    'GlassDoor',
                                                                                    data['exterior_glass_door_standards_construction_type'],
                                                                                    data['exterior_glass_door_building_category']))
    end
    if data['exterior_overhead_door_standards_construction_type'] && data['exterior_overhead_door_building_category']
      exterior_subsurfaces.setOverheadDoorConstruction(model_find_and_add_construction(model,
                                                                                       climate_zone_set,
                                                                                       'ExteriorDoor',
                                                                                       data['exterior_overhead_door_standards_construction_type'],
                                                                                       data['exterior_overhead_door_building_category']))
    end
    if data['exterior_skylight_standards_construction_type'] && data['exterior_skylight_building_category']
      exterior_subsurfaces.setSkylightConstruction(model_find_and_add_construction(model,
                                                                                   climate_zone_set,
                                                                                   'Skylight',
                                                                                   data['exterior_skylight_standards_construction_type'],
                                                                                   data['exterior_skylight_building_category']))
    end
    if (construction_name = data['tubular_daylight_domes'])
      exterior_subsurfaces.setTubularDaylightDomeConstruction(model_add_construction(model, construction_name))
    end
    if (construction_name = data['tubular_daylight_diffusers'])
      exterior_subsurfaces.setTubularDaylightDiffuserConstruction(model_add_construction(model, construction_name))
    end

    # Interior sub surfaces constructions
    interior_subsurfaces = OpenStudio::Model::DefaultSubSurfaceConstructions.new(model)
    construction_set.setDefaultInteriorSubSurfaceConstructions(interior_subsurfaces)
    if (construction_name = data['interior_fixed_windows'])
      interior_subsurfaces.setFixedWindowConstruction(model_add_construction(model, construction_name))
    end
    if (construction_name = data['interior_operable_windows'])
      interior_subsurfaces.setOperableWindowConstruction(model_add_construction(model, construction_name))
    end
    if (construction_name = data['interior_doors'])
      interior_subsurfaces.setDoorConstruction(model_add_construction(model, construction_name))
    end

    # Other constructions
    if (construction_name = data['interior_partitions'])
      construction_set.setInteriorPartitionConstruction(model_add_construction(model, construction_name))
    end
    if (construction_name = data['space_shading'])
      construction_set.setSpaceShadingConstruction(model_add_construction(model, construction_name))
    end
    if (construction_name = data['building_shading'])
      construction_set.setBuildingShadingConstruction(model_add_construction(model, construction_name))
    end
    if (construction_name = data['site_shading'])
      construction_set.setSiteShadingConstruction(model_add_construction(model, construction_name))
    end

    # componentize the construction set
    # construction_set_component = construction_set.createComponent

    # Return the construction set
    return OpenStudio::Model::OptionalDefaultConstructionSet.new(construction_set)
  end

  # Adds a curve from the OpenStudio-Standards dataset to the model based on the curve name.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param curve_name [String] name of the curve
  # @return [OpenStudio::Model::Curve] curve object, nil if not found
  def model_add_curve(model, curve_name)
    # First check model and return curve if it already exists
    existing_curves = []
    existing_curves += model.getCurveLinears
    existing_curves += model.getCurveCubics
    existing_curves += model.getCurveQuadratics
    existing_curves += model.getCurveBicubics
    existing_curves += model.getCurveBiquadratics
    existing_curves += model.getCurveQuadLinears
    existing_curves += model.getTableMultiVariableLookups
    existing_curves += model.getTableLookups
    existing_curves.sort.each do |curve|
      if curve.name.get.to_s == curve_name
        OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Model', "Already added curve: #{curve_name}")
        return curve
      end
    end

    # Find curve data
    data = model_find_object(standards_data['curves'], 'name' => curve_name)
    if data.nil?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.Model.Model', "Could not find a curve called '#{curve_name}' in the standards.")
      return nil
    end

    # Make the correct type of curve
    case data['form']
      when 'Linear'
        curve = OpenStudio::Model::CurveLinear.new(model)
        curve.setName(data['name'])
        curve.setCoefficient1Constant(data['coeff_1'])
        curve.setCoefficient2x(data['coeff_2'])
        curve.setMinimumValueofx(data['minimum_independent_variable_1']) if data['minimum_independent_variable_1']
        curve.setMaximumValueofx(data['maximum_independent_variable_1']) if data['maximum_independent_variable_1']
        curve.setMinimumCurveOutput(data['minimum_dependent_variable_output']) if data['minimum_dependent_variable_output']
        curve.setMaximumCurveOutput(data['maximum_dependent_variable_output']) if data['maximum_dependent_variable_output']
        return curve
      when 'Cubic'
        curve = OpenStudio::Model::CurveCubic.new(model)
        curve.setName(data['name'])
        curve.setCoefficient1Constant(data['coeff_1'])
        curve.setCoefficient2x(data['coeff_2'])
        curve.setCoefficient3xPOW2(data['coeff_3'])
        curve.setCoefficient4xPOW3(data['coeff_4'])
        curve.setMinimumValueofx(data['minimum_independent_variable_1']) if data['minimum_independent_variable_1']
        curve.setMaximumValueofx(data['maximum_independent_variable_1']) if data['maximum_independent_variable_1']
        curve.setMinimumCurveOutput(data['minimum_dependent_variable_output']) if data['minimum_dependent_variable_output']
        curve.setMaximumCurveOutput(data['maximum_dependent_variable_output']) if data['maximum_dependent_variable_output']
        return curve
      when 'Quadratic'
        curve = OpenStudio::Model::CurveQuadratic.new(model)
        curve.setName(data['name'])
        curve.setCoefficient1Constant(data['coeff_1'])
        curve.setCoefficient2x(data['coeff_2'])
        curve.setCoefficient3xPOW2(data['coeff_3'])
        curve.setMinimumValueofx(data['minimum_independent_variable_1']) if data['minimum_independent_variable_1']
        curve.setMaximumValueofx(data['maximum_independent_variable_1']) if data['maximum_independent_variable_1']
        curve.setMinimumCurveOutput(data['minimum_dependent_variable_output']) if data['minimum_dependent_variable_output']
        curve.setMaximumCurveOutput(data['maximum_dependent_variable_output']) if data['maximum_dependent_variable_output']
        return curve
      when 'BiCubic'
        curve = OpenStudio::Model::CurveBicubic.new(model)
        curve.setName(data['name'])
        curve.setCoefficient1Constant(data['coeff_1'])
        curve.setCoefficient2x(data['coeff_2'])
        curve.setCoefficient3xPOW2(data['coeff_3'])
        curve.setCoefficient4y(data['coeff_4'])
        curve.setCoefficient5yPOW2(data['coeff_5'])
        curve.setCoefficient6xTIMESY(data['coeff_6'])
        curve.setCoefficient7xPOW3(data['coeff_7'])
        curve.setCoefficient8yPOW3(data['coeff_8'])
        curve.setCoefficient9xPOW2TIMESY(data['coeff_9'])
        curve.setCoefficient10xTIMESYPOW2(data['coeff_10'])
        curve.setMinimumValueofx(data['minimum_independent_variable_1']) if data['minimum_independent_variable_1']
        curve.setMaximumValueofx(data['maximum_independent_variable_1']) if data['maximum_independent_variable_1']
        curve.setMinimumValueofy(data['minimum_independent_variable_2']) if data['minimum_independent_variable_2']
        curve.setMaximumValueofy(data['maximum_independent_variable_2']) if data['maximum_independent_variable_2']
        curve.setMinimumCurveOutput(data['minimum_dependent_variable_output']) if data['minimum_dependent_variable_output']
        curve.setMaximumCurveOutput(data['maximum_dependent_variable_output']) if data['maximum_dependent_variable_output']
        return curve
      when 'BiQuadratic'
        curve = OpenStudio::Model::CurveBiquadratic.new(model)
        curve.setName(data['name'])
        curve.setCoefficient1Constant(data['coeff_1'])
        curve.setCoefficient2x(data['coeff_2'])
        curve.setCoefficient3xPOW2(data['coeff_3'])
        curve.setCoefficient4y(data['coeff_4'])
        curve.setCoefficient5yPOW2(data['coeff_5'])
        curve.setCoefficient6xTIMESY(data['coeff_6'])
        curve.setMinimumValueofx(data['minimum_independent_variable_1']) if data['minimum_independent_variable_1']
        curve.setMaximumValueofx(data['maximum_independent_variable_1']) if data['maximum_independent_variable_1']
        curve.setMinimumValueofy(data['minimum_independent_variable_2']) if data['minimum_independent_variable_2']
        curve.setMaximumValueofy(data['maximum_independent_variable_2']) if data['maximum_independent_variable_2']
        curve.setMinimumCurveOutput(data['minimum_dependent_variable_output']) if data['minimum_dependent_variable_output']
        curve.setMaximumCurveOutput(data['maximum_dependent_variable_output']) if data['maximum_dependent_variable_output']
        return curve
      when 'BiLinear'
        curve = OpenStudio::Model::CurveBiquadratic.new(model)
        curve.setName(data['name'])
        curve.setCoefficient1Constant(data['coeff_1'])
        curve.setCoefficient2x(data['coeff_2'])
        curve.setCoefficient4y(data['coeff_3'])
        curve.setMinimumValueofx(data['minimum_independent_variable_1']) if data['minimum_independent_variable_1']
        curve.setMaximumValueofx(data['maximum_independent_variable_1']) if data['maximum_independent_variable_1']
        curve.setMinimumValueofy(data['minimum_independent_variable_2']) if data['minimum_independent_variable_2']
        curve.setMaximumValueofy(data['maximum_independent_variable_2']) if data['maximum_independent_variable_2']
        curve.setMinimumCurveOutput(data['minimum_dependent_variable_output']) if data['minimum_dependent_variable_output']
        curve.setMaximumCurveOutput(data['maximum_dependent_variable_output']) if data['maximum_dependent_variable_output']
        return curve
      when 'QuadLinear'
        curve = OpenStudio::Model::CurveQuadLinear.new(model)
        curve.setName(data['name'])
        curve.setCoefficient1Constant(data['coeff_1'])
        curve.setCoefficient2w(data['coeff_2'])
        curve.setCoefficient3x(data['coeff_3'])
        curve.setCoefficient4y(data['coeff_4'])
        curve.setCoefficient5z(data['coeff_5'])
        curve.setMinimumValueofw(data['minimum_independent_variable_w'])
        curve.setMaximumValueofw(data['maximum_independent_variable_w'])
        curve.setMinimumValueofx(data['minimum_independent_variable_x'])
        curve.setMaximumValueofx(data['maximum_independent_variable_x'])
        curve.setMinimumValueofy(data['minimum_independent_variable_y'])
        curve.setMaximumValueofy(data['maximum_independent_variable_y'])
        curve.setMinimumValueofz(data['minimum_independent_variable_z'])
        curve.setMaximumValueofz(data['maximum_independent_variable_z'])
        curve.setMinimumCurveOutput(data['minimum_dependent_variable_output'])
        curve.setMaximumCurveOutput(data['maximum_dependent_variable_output'])
        return curve
      when 'TableLookup', 'LookupTable', 'TableMultiVariableLookup', 'MultiVariableLookupTable'
        num_ind_var = data['number_independent_variables'].to_i
        if model.version < OpenStudio::VersionString.new('3.7.0')
          # Use TableMultiVariableLookup object
          table = OpenStudio::Model::TableMultiVariableLookup.new(model, num_ind_var)
          table.setInterpolationMethod(data['interpolation_method'])
          table.setNumberofInterpolationPoints(data['number_of_interpolation_points'])
          table.setCurveType(data['curve_type'])
          table.setTableDataFormat('SingleLineIndependentVariableWithMatrix')
          table.setNormalizationReference(data['normalization_reference'].to_f)

          # set table limits
          table.setMinimumValueofX1(data['minimum_independent_variable_1'].to_f)
          table.setMaximumValueofX1(data['maximum_independent_variable_1'].to_f)
          table.setInputUnitTypeforX1(data['input_unit_type_x1'])
          if num_ind_var == 2
            table.setMinimumValueofX2(data['minimum_independent_variable_2'].to_f)
            table.setMaximumValueofX2(data['maximum_independent_variable_2'].to_f)
            table.setInputUnitTypeforX2(data['input_unit_type_x2'])
          end

          # add data points
          data_points = data.each.select { |key, value| key.include? 'data_point' }
          data_points.each do |key, value|
            if num_ind_var == 1
              table.addPoint(value.split(',')[0].to_f, value.split(',')[1].to_f)
            elsif num_ind_var == 2
              table.addPoint(value.split(',')[0].to_f, value.split(',')[1].to_f, value.split(',')[2].to_f)
            end
          end
        else
          # Use TableLookup Object
          table = OpenStudio::Model::TableLookup.new(model)
          table.setNormalizationDivisor(data['normalization_reference'].to_f)

          # sorting data in ascending order
          data_points = data.each.select { |key, value| key.include? 'data_point' }
          data_points = data_points.sort_by { |item| item[1].split(',').map(&:to_f) }
          data_points.each do |key, value|
            var_dep = value.split(',')[2].to_f
            table.addOutputValue(var_dep)
          end
          num_ind_var.times do |i|
            table_indvar = OpenStudio::Model::TableIndependentVariable.new(model)
            table_indvar.setName(data['name'] + "_ind_#{i + 1}")
            table_indvar.setInterpolationMethod(data['interpolation_method'])

            # set table limits
            table_indvar.setMinimumValue(data["minimum_independent_variable_#{i + 1}"].to_f)
            table_indvar.setMaximumValue(data["maximum_independent_variable_#{i + 1}"].to_f)
            table_indvar.setUnitType(data["input_unit_type_x#{i + 1}"].to_s)

            # add data points
            var_ind_unique = data_points.map { |key, value| value.split(',')[i].to_f }.uniq
            var_ind_unique.each { |var_ind| table_indvar.addValue(var_ind) }
            table.addIndependentVariable(table_indvar)
          end
        end
        table.setName(data['name'])
        table.setOutputUnitType(data['output_unit_type'])
        return table
      else
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.Model.Model', "#{curve_name}' has an invalid form: #{data['form']}', cannot create this curve.")
        return nil
    end
  end

  # This is used by other methods to get the climate zone and building type from a model.
  # It has logic to break office into small,
  # medium or large based on building area that can be turned off
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param remap_office [Boolean] re-map small office or leave it alone
  # @return [Hash] key for climate zone, building type, and standards template.  All values are strings.
  def model_get_building_properties(model, remap_office = true)
    # get climate zone from model
    climate_zone = OpenstudioStandards::Weather.model_get_climate_zone(model)

    # get building type from model
    building_type = ''
    if model.getBuilding.standardsBuildingType.is_initialized
      building_type = model.getBuilding.standardsBuildingType.get
    end

    # map office building type to small medium or large
    if building_type == 'Office' && remap_office
      open_studio_area = model.getBuilding.floorArea
      building_type = model_remap_office(model, open_studio_area)
    end

    # get standards template
    if model.getBuilding.standardsTemplate.is_initialized
      standards_template = model.getBuilding.standardsTemplate.get
    end

    results = {}
    results['climate_zone'] = climate_zone
    results['building_type'] = building_type
    results['standards_template'] = standards_template

    return results
  end

  # remap office to one of the prototype buildings
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param floor_area [Double] floor area (m^2)
  # @return [String] SmallOffice, MediumOffice, LargeOffice
  def model_remap_office(model, floor_area)
    # prototype small office approx 500 m^2
    # prototype medium office approx 5000 m^2
    # prototype large office approx 50,000 m^2
    # map office building type to small medium or large
    building_type = if floor_area < 2750
                      'SmallOffice'
                    elsif floor_area < 25_250
                      'MediumOffice'
                    else
                      'LargeOffice'
                    end
  end

  # Apply the standard construction to each surface in the model, based on the construction type currently assigned.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @param wwr_building_type [String] building type used for defining window to wall ratio, e.g. 'Office > 50,000 sq ft'
  # @param wwr_info [Hash] A map that maps each building area type to its correspondent wwr.
  # @return [Boolean] returns true if successful, false if not
  def model_apply_standard_constructions(model, climate_zone, wwr_building_type: nil, wwr_info: {})
    types_to_modify = []

    # Possible boundary conditions are
    # Adiabatic
    # Surface
    # Outdoors
    # Ground
    # Foundation
    # GroundFCfactorMethod
    # OtherSideCoefficients
    # OtherSideConditionsModel
    # GroundSlabPreprocessorAverage
    # GroundSlabPreprocessorCore
    # GroundSlabPreprocessorPerimeter
    # GroundBasementPreprocessorAverageWall
    # GroundBasementPreprocessorAverageFloor
    # GroundBasementPreprocessorUpperWall
    # GroundBasementPreprocessorLowerWall

    # Possible surface types are
    # Floor
    # Wall
    # RoofCeiling
    # FixedWindow
    # OperableWindow
    # Door
    # GlassDoor
    # OverheadDoor
    # Skylight
    # TubularDaylightDome
    # TubularDaylightDiffuser

    # Create an array of surface types
    types_to_modify << ['Outdoors', 'Floor']
    types_to_modify << ['Outdoors', 'Wall']
    types_to_modify << ['Outdoors', 'RoofCeiling']
    types_to_modify << ['Outdoors', 'FixedWindow']
    types_to_modify << ['Outdoors', 'OperableWindow']
    types_to_modify << ['Outdoors', 'Door']
    types_to_modify << ['Outdoors', 'GlassDoor']
    types_to_modify << ['Outdoors', 'ExteriorDoor']
    types_to_modify << ['Outdoors', 'OverheadDoor']
    types_to_modify << ['Outdoors', 'Skylight']
    types_to_modify << ['Surface', 'Floor']
    types_to_modify << ['Surface', 'Wall']
    types_to_modify << ['Surface', 'RoofCeiling']
    types_to_modify << ['Surface', 'FixedWindow']
    types_to_modify << ['Surface', 'OperableWindow']
    types_to_modify << ['Surface', 'Door']
    types_to_modify << ['Surface', 'GlassDoor']
    types_to_modify << ['Surface', 'OverheadDoor']
    types_to_modify << ['Ground', 'Floor']
    types_to_modify << ['Ground', 'Wall']
    types_to_modify << ['Foundation', 'Wall']
    types_to_modify << ['GroundFCfactorMethod', 'Wall']
    types_to_modify << ['OtherSideCoefficients', 'Wall']
    types_to_modify << ['OtherSideConditionsModel', 'Wall']
    types_to_modify << ['GroundBasementPreprocessorAverageWall', 'Wall']
    types_to_modify << ['GroundBasementPreprocessorUpperWall', 'Wall']
    types_to_modify << ['GroundBasementPreprocessorLowerWall', 'Wall']
    types_to_modify << ['Foundation', 'Floor']
    types_to_modify << ['GroundFCfactorMethod', 'Floor']
    types_to_modify << ['OtherSideCoefficients', 'Floor']
    types_to_modify << ['OtherSideConditionsModel', 'Floor']
    types_to_modify << ['GroundSlabPreprocessorAverage', 'Floor']
    types_to_modify << ['GroundSlabPreprocessorCore', 'Floor']
    types_to_modify << ['GroundSlabPreprocessorPerimeter', 'Floor']

    # Find just those surfaces
    surfaces_to_modify = []
    surface_category = {}
    org_surface_boundary_conditions = {}
    types_to_modify.each do |boundary_condition, surface_type|
      # Surfaces
      model.getSurfaces.sort.each do |surf|
        next unless surf.outsideBoundaryCondition == boundary_condition
        next unless surf.surfaceType == surface_type
        # legacy energy code does not require processing surface type surface.
        if surf.outsideBoundaryCondition == 'Surface' && !has_space_conditioning_category
          next
        end

        # Check if surface is adjacent to an unenclosed or unconditioned space (e.g. attic or parking garage)
        if has_space_conditioning_category && surf.outsideBoundaryCondition == 'Surface'
          adj_space = surf.adjacentSurface.get.space.get
          adj_space_cond_type = space_conditioning_category(adj_space)
          if adj_space_cond_type == 'Unconditioned'
            # Get adjacent surface
            adjacent_surf = surf.adjacentSurface.get

            # Store original boundary condition type
            org_surface_boundary_conditions[surf.name.to_s] = adjacent_surf

            # Identify this surface as exterior
            surface_category[surf] = 'ExteriorSurface'

            # Temporary change the surface's boundary condition to 'Outdoors' so it can be assigned a baseline construction
            surf.setOutsideBoundaryCondition('Outdoors')
            adjacent_surf.setOutsideBoundaryCondition('Outdoors')
          end
        elsif boundary_condition == 'Outdoors'
          surface_category[surf] = 'ExteriorSurface'
        elsif ['Ground', 'Foundation', 'GroundFCfactorMethod', 'OtherSideCoefficients', 'OtherSideConditionsModel', 'GroundSlabPreprocessorAverage', 'GroundSlabPreprocessorCore', 'GroundSlabPreprocessorPerimeter', 'GroundBasementPreprocessorAverageWall', 'GroundBasementPreprocessorAverageFloor', 'GroundBasementPreprocessorUpperWall', 'GroundBasementPreprocessorLowerWall'].include?(boundary_condition)
          surface_category[surf] = 'GroundSurface'
        else
          surface_category[surf] = 'NA'
        end
        surfaces_to_modify << surf
      end

      # SubSurfaces
      model.getSubSurfaces.sort.each do |surf|
        next unless surf.outsideBoundaryCondition == boundary_condition
        next unless surf.subSurfaceType == surface_type

        surface_category[surf] = 'ExteriorSubSurface'
        surfaces_to_modify << surf
      end
    end

    # Modify these surfaces
    prev_created_consts = {}
    surfaces_to_modify.sort.each do |surf|
      if has_space_conditioning_category
        # Get space conditioning
        space = surf.space.get
        space_cond_type = space_conditioning_category(space)
        # Do not modify constructions for unconditioned spaces
        prev_created_consts = planar_surface_apply_standard_construction(surf, climate_zone, prev_created_consts, wwr_building_type, wwr_info, surface_category[surf]) unless space_cond_type == 'Unconditioned'
      else
        # No space conditioning requirements for legacy code
        prev_created_consts = planar_surface_apply_standard_construction(surf, climate_zone, prev_created_consts, wwr_building_type, wwr_info, surface_category[surf])
      end

      # Reset boundary conditions to original if they were temporary modified
      if org_surface_boundary_conditions.include?(surf.name.to_s)
        surf.setAdjacentSurface(org_surface_boundary_conditions[surf.name.to_s])
      end
    end

    # List the unique array of constructions
    if prev_created_consts.empty?
      OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.Model', 'None of the constructions in your proposed model have both Intended Surface Type and Standards Construction Type')
    else
      prev_created_consts.each do |surf_type, construction|
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "For #{surf_type.join(' ')}, applied #{construction.name}.")
      end
    end

    true
  end

  # Returns standards data for selected construction
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param intended_surface_type [String] the surface type
  # @param standards_construction_type [String]  the type of construction
  # @param building_category [String] the type of building
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [Hash] hash of construction properties
  def model_get_construction_properties(model, intended_surface_type, standards_construction_type, building_category, climate_zone = nil)
    # get climate_zone_set
    climate_zone = model_get_building_properties(model)['climate_zone'] if climate_zone.nil?
    climate_zone_set = model_find_climate_zone_set(model, climate_zone)

    # populate search hash
    search_criteria = {
      'template' => template,
      'climate_zone_set' => climate_zone_set,
      'intended_surface_type' => intended_surface_type,
      'standards_construction_type' => standards_construction_type,
      'building_category' => building_category
    }

    # switch to use this but update test in standards and measures to load this outside of the method
    construction_properties = model_find_object(standards_data['construction_properties'], search_criteria)

    if !construction_properties
      # Search again use climate zone (e.g. 3) instead of sub-climate zone (3A)
      search_criteria['climate_zone_set'] = climate_zone_set[0..-2]
      construction_properties = model_find_object(standards_data['construction_properties'], search_criteria)
    end

    return construction_properties
  end

  # Returns standards data for selected construction set
  #
  # @param building_type [String] the type of building
  # @param space_type [String] space type within the building type. Typically nil.
  # @return [Hash] hash of construction set data
  def model_get_construction_set(building_type, space_type = nil)
    # populate search hash
    search_criteria = {
      'template' => template,
      'building_type' => building_type,
      'space_type' => space_type
    }

    # Search construction sets table for the exterior wall building category and construction type
    construction_set_data = model_find_object(standards_data['construction_sets'], search_criteria)

    return construction_set_data
  end

  # Remove all HVAC that will be replaced during the performance rating method baseline generation.
  # This does not include plant loops that serve WaterUse:Equipment or Fan:ZoneExhaust
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def model_remove_prm_hvac(model)
    # Plant loops
    model.getPlantLoops.sort.each do |loop|
      # Don't remove service water heating loops
      next if plant_loop_swh_loop?(loop)

      loop.remove
    end

    # Air loops
    model.getAirLoopHVACs.each do |air_loop|
      # Don't remove airloops representing non-mechanically cooled systems
      if air_loop.additionalProperties.hasFeature('non_mechanically_cooled')
        # Remove heating coil on
        air_loop.supplyComponents.each do |supply_comp|
          # Remove standalone heating coils
          if supply_comp.iddObjectType.valueName.to_s.include?('OS_Coil_Heating')
            supply_comp.remove
          # Remove heating coils wrapped in a unitary system
          elsif supply_comp.iddObjectType.valueName.to_s.include?('OS_AirLoopHVAC_UnitarySystem')
            unitary_system = supply_comp.to_AirLoopHVACUnitarySystem.get
            htg_coil = unitary_system.heatingCoil
            if htg_coil.is_initialized
              htg_coil = htg_coil.get
              unitary_system.resetCoolingCoil
              htg_coil.remove
            end
          end
        end
      else
        air_loop.remove
      end
    end

    # Zone equipment
    model.getThermalZones.sort.each do |zone|
      zone.equipment.each do |zone_equipment|
        next if zone_equipment.to_FanZoneExhaust.is_initialized

        zone_equipment.remove unless zone.additionalProperties.hasFeature('non_mechanically_cooled')
      end
    end

    # Outdoor VRF units (not in zone, not in loops)
    model.getAirConditionerVariableRefrigerantFlows.each(&:remove)

    # Air loop dedicated outdoor air systems
    model.getAirLoopHVACDedicatedOutdoorAirSystems.each(&:remove)

    return true
  end

  # Remove external shading devices. Site shading will not be impacted.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def model_remove_external_shading_devices(model)
    shading_surfaces_removed = 0
    model.getShadingSurfaceGroups.sort.each do |shade_group|
      # Skip Site shading
      next if shade_group.shadingSurfaceType == 'Site'

      # Space shading surfaces should be removed
      shading_surfaces_removed += shade_group.shadingSurfaces.size
      shade_group.remove
    end

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Removed #{shading_surfaces_removed} external shading devices.")

    return true
  end

  # Changes the sizing parameters to the PRM specifications.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def model_apply_prm_sizing_parameters(model)
    clg = 1.15
    htg = 1.25

    sizing_params = model.getSizingParameters
    sizing_params.setHeatingSizingFactor(htg)
    sizing_params.setCoolingSizingFactor(clg)

    OpenStudio.logFree(OpenStudio::Info, 'openstudio.prototype.Model', "Set sizing factors to #{htg} for heating and #{clg} for cooling.")
    return true
  end

  # Returns average daily hot water consumption by building type
  # recommendations from 2011 ASHRAE Handbook - HVAC Applications Table 7 section 50.14
  # Not all building types are included in lookup
  # some recommendations have multiple values based on number of units.
  # Will return an array of hashes. Many may have one array entry.
  # all values other than block size are gallons.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Array] array of hashes. Each array entry based on different capacity
  #   specific to building type. Array will be empty for some building types.
  def model_find_ashrae_hot_water_demand(model)
    # @todo for types not in table use standards area normalized swh values

    # get building type
    building_data = model_get_building_properties(model)
    building_type = building_data['building_type']

    result = []
    case building_type
    when 'FullServiceRestaurant'
      result << { units: 'meal', block: nil, max_hourly: 1.5, max_daily: 11.0, avg_day_unit: 2.4 }
    when 'Hospital', 'Outpatient', 'Retail', 'StripMall', 'SuperMarket', 'Warehouse', 'SmallDataCenterLowITE', 'SmallDataCenterHighITE', 'LargeDataCenterLowITE', 'LargeDataCenterHighITE', 'Laboratory'
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', "No SWH rules of thumbs for #{building_type}.")
    when 'LargeHotel', 'SmallHotel'
      result << { units: 'unit', block: 20, max_hourly: 6.0, max_daily: 35.0, avg_day_unit: 24.0 }
      result << { units: 'unit', block: 60, max_hourly: 5.0, max_daily: 25.0, avg_day_unit: 14.0 }
      result << { units: 'unit', block: 100, max_hourly: 4.0, max_daily: 15.0, avg_day_unit: 10.0 }
    when 'MidriseApartment'
      result << { units: 'unit', block: 20, max_hourly: 12.0, max_daily: 80.0, avg_day_unit: 42.0 }
      result << { units: 'unit', block: 50, max_hourly: 10.0, max_daily: 73.0, avg_day_unit: 40.0 }
      result << { units: 'unit', block: 75, max_hourly: 8.5, max_daily: 66.0, avg_day_unit: 38.0 }
      result << { units: 'unit', block: 100, max_hourly: 7.0, max_daily: 60.0, avg_day_unit: 37.0 }
      result << { units: 'unit', block: 200, max_hourly: 5.0, max_daily: 50.0, avg_day_unit: 35.0 }
    when 'Office', 'LargeOffice', 'MediumOffice', 'SmallOffice', 'LargeOfficeDetailed', 'MediumOfficeDetailed', 'SmallOfficeDetailed'
      result << { units: 'person', block: nil, max_hourly: 0.4, max_daily: 2.0, avg_day_unit: 1.0 }
    when 'PrimarySchool'
      result << { units: 'student', block: nil, max_hourly: 0.6, max_daily: 1.5, avg_day_unit: 0.6 }
    when 'QuickServiceRestaurant'
      result << { units: 'meal', block: nil, max_hourly: 0.7, max_daily: 6.0, avg_day_unit: 0.7 }
    when 'SecondarySchool'
      result << { units: 'student', block: nil, max_hourly: 1.0, max_daily: 3.6, avg_day_unit: 1.8 }
    else
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', "Didn't find expected building type. As a result can't determine hot water demand recommendations")
    end

    return result
  end

  # Returns average daily hot water consumption for residential buildings
  # gal/day from ICC IECC 2015 Residential Standard Reference Design
  # from Table R405.5.2(1)
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param units_per_bldg [Double] number of units in the building
  # @param bedrooms_per_unit [Double] number of bedrooms per unit
  # @return [Double] gal/day
  def model_find_icc_iecc_2015_hot_water_demand(model, units_per_bldg, bedrooms_per_unit)
    swh_gal_per_day = units_per_bldg * (30.0 + (10.0 * bedrooms_per_unit))

    return swh_gal_per_day
  end

  # Returns average daily internal loads for residential buildings from Table R405.5.2(1)
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param units_per_bldg [Double] number of units in the building
  # @param bedrooms_per_unit [Double] number of bedrooms per unit
  # @return [Hash] mech_vent_cfm, infiltration_ach, igain_btu_per_day, internal_mass_lbs
  def model_find_icc_iecc_2015_internal_loads(model, units_per_bldg, bedrooms_per_unit)
    # get total and conditioned floor area
    total_floor_area = model.getBuilding.floorArea
    if model.getBuilding.conditionedFloorArea.is_initialized
      conditioned_floor_area = model.getBuilding.conditionedFloorArea.get
    else
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', 'Cannot find conditioned floor area, will use total floor area.')
      conditioned_floor_area = total_floor_area
    end

    # get climate zone value
    climate_zone = OpenstudioStandards::Weather.model_get_climate_zone(model)

    internal_loads = {}
    internal_loads['mech_vent_cfm'] = units_per_bldg * ((0.01 * conditioned_floor_area) + (7.5 * (bedrooms_per_unit + 1.0)))
    internal_loads['infiltration_ach'] = if ['1A', '1B', '2A', '2B'].include? climate_zone_value
                                           5.0
                                         else
                                           3.0
                                         end
    internal_loads['igain_btu_per_day'] = units_per_bldg * (17_900.0 + (23.8 * conditioned_floor_area) + (4104.0 * bedrooms_per_unit))
    internal_loads['internal_mass_lbs'] = total_floor_area * 8.0

    return internal_loads
  end

  # Helper method to make a shortened version of a name that will be readable in a GUI.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @param building_type [String] the building type
  # @param spc_type [String] the space type
  # @return [String] string of the model name
  def model_make_name(model, climate_zone, building_type, spc_type)
    climate_zone = climate_zone.gsub('ClimateZone ', 'CZ')
    if climate_zone == 'CZ1-8'
      climate_zone = ''
    end

    case building_type
    when 'FullServiceRestaurant'
      building_type = 'FullSrvRest'
    when 'Hospital'
      building_type = 'Hospital'
    when 'LargeHotel'
      building_type = 'LrgHotel'
    when 'LargeOffice'
      building_type = 'LrgOffice'
    when 'MediumOffice'
      building_type = 'MedOffice'
    when 'MidriseApartment'
      building_type = 'MidApt'
    when 'HighriseApartment'
      building_type = 'HighApt'
    when 'Office'
      building_type = 'Office'
    when 'Outpatient'
      building_type = 'Outpatient'
    when 'PrimarySchool'
      building_type = 'PriSchl'
    when 'QuickServiceRestaurant'
      building_type = 'QckSrvRest'
    when 'Retail'
      building_type = 'Retail'
    when 'SecondarySchool'
      building_type = 'SecSchl'
    when 'SmallHotel'
      building_type = 'SmHotel'
    when 'SmallOffice'
      building_type = 'SmOffice'
    when 'StripMall'
      building_type = 'StMall'
    when 'SuperMarket'
      building_type = 'SpMarket'
    when 'Warehouse'
      building_type = 'Warehouse'
    when 'SmallDataCenterLowITE'
      building_type = 'SmDCLowITE'
    when 'SmallDataCenterHighITE'
      building_type = 'SmDCHighITE'
    when 'LargeDataCenterLowITE'
      building_type = 'LrgDCLowITE'
    when 'LargeDataCenterHighITE'
      building_type = 'LrgDCHighITE'
    when 'Laboratory'
      building_type = 'Laboratory'
    when 'TallBuilding'
      building_type = 'TallBldg'
    when 'SuperTallBuilding'
      building_type = 'SpTallBldg'
    end

    parts = [template]

    unless building_type.nil?
      parts << building_type
    end

    unless spc_type.nil?
      parts << spc_type
    end

    unless climate_zone.empty?
      parts << climate_zone
    end

    result = parts.join(' - ')

    return result
  end

  # Helper method to find out which climate zone set contains a specific climate zone.
  # Returns climate zone set name as String if success, nil if not found.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [String] climate zone set
  def model_find_climate_zone_set(model, climate_zone)
    result = nil

    possible_climate_zone_sets = []
    standards_data['climate_zone_sets'].each do |climate_zone_set|
      if climate_zone_set['climate_zones'].include?(climate_zone)
        possible_climate_zone_sets << climate_zone_set['name']
      end
    end

    # Check the results
    if possible_climate_zone_sets.empty?
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', "Cannot find a climate zone set containing #{climate_zone}.  Make sure to use ASHRAE standards with ASHRAE climate zones and DEER or CA Title 24 standards with CEC climate zones.")
    elsif possible_climate_zone_sets.size > 2
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', "Found more than 2 climate zone sets containing #{climate_zone}; will return last matching climate zone set.")
    end

    # Get the climate zone from the possible set
    climate_zone_set = model_get_climate_zone_set_from_list(model, possible_climate_zone_sets)

    # Check that a climate zone set was found
    if climate_zone_set.nil?
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', "Cannot find a climate zone set in standard #{template}")
    end

    return climate_zone_set
  end

  # Determine which climate zone to use.
  # Defaults to the least specific climate zone set.
  # For example, 2A and 2 both contain 2A, so use 2.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param possible_climate_zone_sets [Array] climate zone sets
  # @return [String] climate zone ses
  def model_get_climate_zone_set_from_list(model, possible_climate_zone_sets)
    climate_zone_set = possible_climate_zone_sets.max
    return climate_zone_set
  end

  # This method ensures that all spaces with spacetypes defined contain at least a standardSpaceType appropriate for the template.
  # So, if any space with a space type defined does not have a Stnadard spacetype, or is undefined, an error will stop
  # with information that the spacetype needs to be defined.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def model_validate_standards_spacetypes_in_model(model)
    error_string = ''
    # populate search hash
    model.getSpaces.sort.each do |space|
      unless space.spaceType.empty?
        if space.spaceType.get.standardsSpaceType.empty? || space.spaceType.get.standardsBuildingType.empty?
          error_string << "Space: #{space.name} has SpaceType of #{space.spaceType.get.name} but the standardSpaceType or standardBuildingType  is undefined. Please use an appropriate standardSpaceType for #{template}\n"
          next
        else
          search_criteria = {
            'template' => template,
            'building_type' => space.spaceType.get.standardsBuildingType.get,
            'space_type' => space.spaceType.get.standardsSpaceType.get
          }
          # lookup space type properties
          space_type_properties = model_find_object(standards_data['space_types'], search_criteria)
          if space_type_properties.nil?
            error_string << "Could not find spacetype of criteria : #{search_criteria}. Please ensure you have a valid standardSpaceType and stantdardBuildingType defined.\n"
            space_type_properties = {}
          end
        end
      end
    end
    return true if error_string == ''

    # else
    OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', error_string)
    return false
  end

  # Create sorted hash of stories with data need to determine effective number of stories above and below grade
  # the key should be the story object, which would allow other measures the ability to for example loop through spaces of the bottom story
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Hash] hash of space types with data in value necessary to determine effective number of stories above and below grade
  def model_create_story_hash(model)
    story_hash = {}

    # loop through stories
    model.getBuildingStorys.sort.each do |story|
      # skip of story doesn't have any spaces
      next if story.spaces.empty?

      story_min_z = nil
      story_zone_multipliers = []
      story_spaces_part_of_floor_area = []
      story_spaces_not_part_of_floor_area = []
      story_ext_wall_area = 0.0
      story_ground_wall_area = 0.0

      # loop through space surfaces to find min z value
      story.spaces.each do |space|
        # skip of space doesn't have any geometry
        next if space.surfaces.empty?

        # get space multiplier
        story_zone_multipliers << space.multiplier

        # space part of floor area check
        if space.partofTotalFloorArea
          story_spaces_part_of_floor_area << space
        else
          story_spaces_not_part_of_floor_area << space
        end

        # update exterior wall area (not sure if this is net or gross)
        story_ext_wall_area += space.exteriorWallArea

        space_min_z = nil
        z_points = []
        space.surfaces.each do |surface|
          surface.vertices.each do |vertex|
            z_points << vertex.z
          end

          # update count of ground wall areas
          next if surface.surfaceType != 'Wall'
          next if surface.outsideBoundaryCondition != 'Ground'

          # @todo make more flexible for slab/basement model.modeling

          story_ground_wall_area += surface.grossArea
        end

        # skip if surface had no vertices
        next if z_points.empty?

        # update story min_z
        space_min_z = z_points.min + space.zOrigin
        if story_min_z.nil? || (story_min_z > space_min_z)
          story_min_z = space_min_z
        end
      end

      # update story hash
      story_hash[story] = {}
      story_hash[story][:min_z] = story_min_z
      story_hash[story][:multipliers] = story_zone_multipliers
      story_hash[story][:part_of_floor_area] = story_spaces_part_of_floor_area
      story_hash[story][:not_part_of_floor_area] = story_spaces_not_part_of_floor_area
      story_hash[story][:ext_wall_area] = story_ext_wall_area
      story_hash[story][:ground_wall_area] = story_ground_wall_area
    end

    # sort hash by min_z low to high
    story_hash = story_hash.sort_by { |k, v| v[:min_z] }

    # reassemble into hash after sorting
    hash = {}
    story_hash.each do |story, props|
      hash[story] = props
    end

    return hash
  end

  # populate this method
  # Determine the effective number of stories above and below grade
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Hash] hash with effective_num_stories_below_grade and effective_num_stories_above_grade
  def model_effective_num_stories(model)
    below_grade = 0
    above_grade = 0

    # call model_create_story_hash(model)
    story_hash = model_create_story_hash(model)

    story_hash.each do |story, hash|
      # skip if no spaces in story are included in the building area
      next if hash[:part_of_floor_area].empty?

      # only count as below grade if ground wall area is greater than ext wall area and story below is also below grade
      if above_grade.zero? && (hash[:ground_wall_area] > hash[:ext_wall_area])
        below_grade += 1 * hash[:multipliers].min
      else
        above_grade += 1 * hash[:multipliers].min
      end
    end

    # populate hash
    effective_num_stories = {}
    effective_num_stories[:below_grade] = below_grade
    effective_num_stories[:above_grade] = above_grade
    effective_num_stories[:story_hash] = story_hash

    return effective_num_stories
  end

  # create space_type_hash with info such as effective_num_spaces, num_units, num_meds, num_meals
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param trust_effective_num_spaces [Boolean] defaults to false - set to true if modeled every space as a real rpp, vs. space as collection of rooms
  # @return [Hash] hash of space types with misc information
  # @todo - add code when determining number of units to makeuse of trust_effective_num_spaces arg
  def model_create_space_type_hash(model, trust_effective_num_spaces = false)
    # assumed class size to deduct teachers from occupant count for classrooms
    typical_class_size = 20.0

    space_type_hash = {}
    model.getSpaceTypes.sort.each do |space_type|
      # get standards info
      stds_bldg_type = space_type.standardsBuildingType
      stds_space_type = space_type.standardsSpaceType
      if stds_bldg_type.is_initialized && stds_space_type.is_initialized && !space_type.spaces.empty?
        stds_bldg_type = stds_bldg_type.get
        stds_space_type = stds_space_type.get
        effective_num_spaces = 0
        floor_area = 0.0
        num_people = 0.0
        num_students = 0.0
        num_units = 0.0
        num_beds = 0.0
        num_people_bldg_total = nil # may need this in future, not same as sumo of people for all space types.
        num_meals = nil
        # determine num_elevators in another method
        # determine num_parking_spots in another method

        # loop through spaces to get mis values
        space_type.spaces.sort.each do |space|
          next unless space.partofTotalFloorArea

          effective_num_spaces += space.multiplier
          floor_area += space.floorArea * space.multiplier
          num_people += space.numberOfPeople * space.multiplier
        end

        # determine number of units
        if stds_bldg_type == 'SmallHotel' && stds_space_type.include?('GuestRoom') # doesn't always == GuestRoom so use include?
          avg_unit_size = OpenStudio.convert(354.2, 'ft^2', 'm^2').get # calculated from prototype
          num_units = floor_area / avg_unit_size
        elsif stds_bldg_type == 'LargeHotel' && stds_space_type.include?('GuestRoom')
          avg_unit_size = OpenStudio.convert(279.7, 'ft^2', 'm^2').get # calculated from prototype
          num_units = floor_area / avg_unit_size
        elsif stds_bldg_type == 'MidriseApartment' && stds_space_type.include?('Apartment')
          avg_unit_size = OpenStudio.convert(949.9, 'ft^2', 'm^2').get # calculated from prototype
          num_units = floor_area / avg_unit_size
        elsif stds_bldg_type == 'HighriseApartment' && stds_space_type.include?('Apartment')
          avg_unit_size = OpenStudio.convert(949.9, 'ft^2', 'm^2').get # calculated from prototype
          num_units = floor_area / avg_unit_size
        elsif stds_bldg_type == 'StripMall'
          avg_unit_size = OpenStudio.convert(22_500.0 / 10.0, 'ft^2', 'm^2').get # calculated from prototype
          num_units = floor_area / avg_unit_size
        elsif stds_bldg_type == 'Htl' && (stds_space_type.include?('GuestRmOcc') || stds_space_type.include?('GuestRmUnOcc'))
          avg_unit_size = OpenStudio.convert(354.2, 'ft^2', 'm^2').get # calculated from prototype
          num_units = floor_area / avg_unit_size
        elsif stds_bldg_type == 'MFm' && (stds_space_type.include?('ResBedroom') || stds_space_type.include?('ResLiving'))
          avg_unit_size = OpenStudio.convert(949.9, 'ft^2', 'm^2').get # calculated from prototype
          num_units = floor_area / avg_unit_size
        elsif stds_bldg_type == 'Mtl' && (stds_space_type.include?('GuestRmOcc') || stds_space_type.include?('GuestRmUnOcc'))
          avg_unit_size = OpenStudio.convert(354.2, 'ft^2', 'm^2').get # calculated from prototype
          num_units = floor_area / avg_unit_size
        elsif stds_bldg_type == 'Nrs' && stds_space_type.include?('PatientRoom')
          avg_unit_size = OpenStudio.convert(354.2, 'ft^2', 'm^2').get # calculated from prototype
          num_units = floor_area / avg_unit_size
        end

        # determine number of beds
        if ((stds_bldg_type == 'Hospital') && ['PatRoom', 'ICU_PatRm', 'ICU_Open'].include?(stds_space_type)) ||
           ((stds_bldg_type == 'Hsp') && ['PatientRoom', 'HspSurgOutptLab', 'HspNursing'].include?(stds_space_type))
          num_beds = num_people
        end

        # determine number of students
        if ['PrimarySchool', 'SecondarySchool', 'EPr', 'ESe', 'ERC', 'EUn', 'ECC'].include?(stds_bldg_type) &&
           (stds_space_type == 'Classroom')
          num_students += num_people * ((typical_class_size - 1.0) / typical_class_size)
        end

        space_type_hash[space_type] = {}
        space_type_hash[space_type][:stds_bldg_type] = stds_bldg_type
        space_type_hash[space_type][:stds_space_type] = stds_space_type
        space_type_hash[space_type][:effective_num_spaces] = effective_num_spaces
        space_type_hash[space_type][:floor_area] = floor_area
        space_type_hash[space_type][:num_people] = num_people
        space_type_hash[space_type][:num_students] = num_students
        space_type_hash[space_type][:num_units] = num_units
        space_type_hash[space_type][:num_beds] = num_beds

        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "For #{space_type.name}, floor area = #{OpenStudio.convert(floor_area, 'm^2', 'ft^2').get.round} ft^2.") unless floor_area == 0.0
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "For #{space_type.name}, number of spaces = #{effective_num_spaces}.") unless effective_num_spaces == 0.0
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "For #{space_type.name}, number of units = #{num_units}.") unless num_units == 0.0
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "For #{space_type.name}, number of people = #{num_people.round}.") unless num_people == 0.0
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "For #{space_type.name}, number of students = #{num_students}.") unless num_students == 0.0
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "For #{space_type.name}, number of beds = #{num_beds}.") unless num_beds == 0.0
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "For #{space_type.name}, number of meals = #{num_meals}.") unless num_meals.nil?

      else
        OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Cannot identify standards building type and space type for #{space_type.name}, it won't be added to space_type_hash.")
      end
    end

    return space_type_hash.sort.to_h
  end

  # This method will limit the subsurface of a given surface_type ("Wall" or "RoofCeiling") to the ratio for the building.
  # This method only reduces subsurface sizes at most.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param ratio [Double] ratio
  # @param surface_type [String] surface type
  # @return [Boolean] returns true if successful, false if not
  def apply_limit_to_subsurface_ratio(model, ratio, surface_type = 'Wall')
    fdwr = get_outdoor_subsurface_ratio(model, surface_type)
    if fdwr <= ratio
      OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Building FDWR of #{fdwr} is already lower than limit of #{ratio.round}%.")
      return true
    end
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "Reducing the size of all windows (by shrinking to centroid) to reduce window area down to the limit of #{ratio.round}%.")
    # Determine the factors by which to reduce the window / door area
    mult = ratio / fdwr
    # Reduce the window area if any of the categories necessary
    model.getSpaces.sort.each do |space|
      # Loop through all surfaces in this space
      space.surfaces.sort.each do |surface|
        # Skip non-outdoor surfaces
        next unless surface.outsideBoundaryCondition == 'Outdoors'
        # Skip non-walls
        next unless surface.surfaceType == surface_type

        # Subsurfaces in this surface
        surface.subSurfaces.sort.each do |ss|
          # Reduce the size of the window
          red = 1.0 - mult
          OpenstudioStandards::Geometry.sub_surface_reduce_area_by_percent_by_shrinking_toward_centroid(ss, red)
        end
      end
    end
    return true
  end

  # This method return the building ratio of subsurface_area / surface_type_area
  # where surface_type can be "Wall" or "RoofCeiling"
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param surface_type [String] surface type
  # @return [Double] surface ratio
  def get_outdoor_subsurface_ratio(model, surface_type = 'Wall')
    surface_area = 0.0
    sub_surface_area = 0
    all_surfaces = []
    all_sub_surfaces = []
    model.getSpaces.sort.each do |space|
      zone = space.thermalZone
      zone_multiplier = nil
      next if zone.empty?

      zone_multiplier = zone.get.multiplier
      space.surfaces.sort.each do |surface|
        if (surface.outsideBoundaryCondition == 'Outdoors') && (surface.surfaceType == surface_type)
          surface_area += surface.grossArea * zone_multiplier
          surface.subSurfaces.sort.each do |sub_surface|
            sub_surface_area += sub_surface.grossArea * sub_surface.multiplier * zone_multiplier
          end
        end
      end
    end
    return fdwr = (sub_surface_area / surface_area)
  end

  # Determines how ventilation for the standard is specified.
  # When 'Sum', all min OA flow rates are added up.  Commonly used by 90.1.
  # When 'Maximum', only the biggest OA flow rate.  Used by T24.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [String] the ventilation method, either Sum or Maximum
  def model_ventilation_method(model)
    building_data = model_get_building_properties(model)
    building_type = building_data['building_type']
    if building_type == 'Laboratory'
      # Laboratory has multiple criteria on ventilation, pick the greatest
      ventilation_method = 'Maximum'
    else
      ventilation_method = 'Sum'
    end

    return ventilation_method
  end

  # Removes all of the unused ResourceObjects
  # (Curves, ScheduleDay, Material, etc.) from the model.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def model_remove_unused_resource_objects(model)
    start_size = model.objects.size
    model.getResourceObjects.sort.each do |obj|
      if obj.directUseCount.zero?
        OpenStudio.logFree(OpenStudio::Debug, 'openstudio.standards.Model', "#{obj.name} is unused; it will be removed.")
        model.removeObject(obj.handle)
      end
    end
    end_size = model.objects.size
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.standards.Model', "The model started with #{start_size} objects and finished with #{end_size} objects after removing unused resource objects.")
    return true
  end

  private

  # This function checks whether it is required to adjust the window to wall ratio based on the model WWR and wwr limit.
  # @param wwr_limit [Double] window to wall ratio limit
  # @param wwr_list [Array] list of wwr of zone conditioning category in a building area type category - residential, nonresidential and semiheated
  # @return [Boolean] True, require adjustment, false not require adjustment.
  def model_does_require_wwr_adjustment?(wwr_limit, wwr_list)
    require_adjustment = false
    wwr_list.each do |wwr|
      require_adjustment = true if wwr > wwr_limit
    end
    return require_adjustment
  end

  # The function is used for codes that requires to adjusted wwr based on building categories for all other types
  #
  # @param bat [String] building area type category
  # @param wwr_list [Array] list of wwr of zone conditioning category in a building area type category - residential, nonresidential and semiheated
  # @return [Double] return adjusted wwr_limit
  def model_get_bat_wwr_target(bat, wwr_list)
    return 40.0
  end

  # Readjusted the WWR for surfaces previously has no windows to meet the
  # overall WWR requirement.
  # This function shall only be called if the maximum WWR value for surfaces with fenestration is lower than 90% due to
  # accommodating the total door surface areas
  #
  # @param residual_ratio [Double] the ratio of residual surfaces among the total wall surface area with no fenestrations
  # @param space [OpenStudio::Model:Space] a space
  # @param model [OpenStudio::Model::Model] openstudio model
  # @return [Boolean] returns true if successful, false if not
  def model_readjust_surface_wwr(residual_ratio, space, model)
    return true
  end

  # Helper method to fill in hourly values
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param day_sch [OpenStudio::Model::ScheduleDay] schedule day object
  # @param sch_type [String] Constant or Hourly
  # @param values [Array<Double>]
  # @return [Boolean] returns true if successful, false if not
  def model_add_vals_to_sch(model, day_sch, sch_type, values)
    if sch_type == 'Constant'
      day_sch.addValue(OpenStudio::Time.new(0, 24, 0, 0), values[0])
    elsif sch_type == 'Hourly'
      24.times do |i|
        next if values[i] == values[i + 1]

        day_sch.addValue(OpenStudio::Time.new(0, i + 1, 0, 0), values[i])
      end
    else
      OpenStudio.logFree(OpenStudio::Error, 'openstudio.standards.Model', "Schedule type: #{sch_type} is not recognized.  Valid choices are 'Constant' and 'Hourly'.")
    end
  end

  # This method goes through certain types of EnergyManagementSystem variables and replaces UIDs with object names.
  # This should be done by the forward translator, and this code should be removed after this bug is fixed:
  # https://github.com/NREL/OpenStudio/issues/2598
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  # @todo remove this method after OpenStudio issue #2598 is fixed.
  def model_temp_fix_ems_references(model)
    # Internal Variables
    model.getEnergyManagementSystemInternalVariables.sort.each do |var|
      # Get the reference field value
      ref = var.internalDataIndexKeyName
      # Convert to UUID
      uid = OpenStudio.toUUID(ref)
      # Get the model object with this UID
      obj = model.getModelObject(uid)
      # If it exists, replace the UID with the object name
      if obj.is_initialized
        var.setInternalDataIndexKeyName(obj.get.name.get)
      end
    end

    return true
  end

  # This method is a catch-all run at the end of create-baseline to make final adjustements to HVAC capacities
  # to account for recent model changes
  # @author Doug Maddox, PNNL
  # @param model
  def model_refine_size_dependent_values(model, sizing_run_dir)
    return true
  end

  # This method rotates the building model from its original position
  #
  # @param model [OpenStudio::Model::Model] OpenStudio Model object
  # @param degs [Integer] Degress of rotation from original position
  #
  # @return [OpenStudio::Model::Model] OpenStudio Model object
  def model_rotate(model, degs)
    building = model.getBuilding
    org_north_axis = building.northAxis
    building.setNorthAxis(org_north_axis + degs)
    OpenStudio.logFree(OpenStudio::Info, 'openstudio.model.Model', "The model was rotated of #{degs} degrees from its original position.")
    return model
  end

  # Retrieves the lowest story in a model
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [OpenStudio::Model::BuildingStory] Lowest story included in the model
  def find_lowest_story(model)
    min_z_story = 1E+10
    lowest_story = nil
    model.getSpaces.sort.each do |space|
      story = space.buildingStory.get
      lowest_story = story if lowest_story.nil?
      space_min_z = OpenstudioStandards::Geometry.building_story_get_minimum_height(story)
      if space_min_z < min_z_story
        min_z_story = space_min_z
        lowest_story = story
      end
    end
    return lowest_story
  end

  # Identifies non mechanically cooled ("nmc") systems, if applicable
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Hash] Zone to nmc system type mapping
  def model_identify_non_mechanically_cooled_systems(model)
    return true
  end

  # Indicate if fan power breakdown (supply, return, and relief)
  # are needed
  #
  # @return [Boolean] true if necessary, false otherwise
  def model_get_fan_power_breakdown
    return false
  end

  # Determine the surface range of a baseline model.
  # The method calculates the window to wall ratio (assuming all spaces are conditioned)
  # and select the range based on the calculated window to wall ratio
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param wwr_parameter [Hash] parameters to choose min and max percent of surfaces,
  #         could be different set in different standard
  # @return [Hash] Hash of minimum_percent_of_surface and maximum_percent_of_surface
  def model_get_percent_of_surface_range(model, wwr_parameter = {})
    return { 'minimum_percent_of_surface' => nil, 'maximum_percent_of_surface' => nil }
  end

  # Default SAT reset type
  #
  # @param air_loop_hvac [OpenStudio::Model::AirLoopHVAC] air loop
  # @return [String] Returns type of SAT reset
  def air_loop_hvac_supply_air_temperature_reset_type(air_loop_hvac)
    return 'warmest_zone'
  end

  # Calculate the window to wall ratio reduction factor
  #
  # @param multiplier [Double] multiplier of the wwr
  # @param surface [OpenStudio::Model:Surface] OpenStudio Surface object
  # @param wwr_target [Double] target window to wall ratio
  # @param total_wall_m2 [Double] total wall area of the category in m2.
  # @param total_wall_with_fene_m2 [Double] total wall area of the category with fenestrations in m2.
  # @param total_fene_m2 [Double] total fenestration area
  # @param total_plenum_wall_m2 [Double] total sqaure meter of a plenum
  # @return [Double] reduction factor
  def surface_get_wwr_reduction_ratio(multiplier,
                                      surface,
                                      wwr_building_type: 'All others',
                                      wwr_target: 0.0,
                                      total_wall_m2: 0.0,
                                      total_wall_with_fene_m2: 0.0,
                                      total_fene_m2: 0.0,
                                      total_plenum_wall_m2: 0.0)
    return 1.0 - multiplier
  end

  # A template method that handles the loading of user input data from multiple sources
  # include data source from:
  # 1. user data csv files
  # 2. data from measure and OpenStudio interface
  # @param [OpenStudio:model:Model] model
  # @param [String] climate_zone
  # @param [String] sizing_run_dir
  # @param [String] default_hvac_building_type
  # @param [String] default_wwr_building_type
  # @param [String] default_swh_building_type
  # @param [Hash] bldg_type_hvac_zone_hash A hash maps building type for hvac to a list of thermal zones
  # @return [Boolean] returns true
  def handle_user_input_data(model, climate_zone, sizing_run_dir, default_hvac_building_type, default_wwr_building_type, default_swh_building_type, bldg_type_hvac_zone_hash)
    return true
  end

  # Template method for adding a setpoint manager for a coil control logic to a heating coil.
  # ASHRAE 90.1-2019 Appendix G.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model
  # @param thermal_zones [Array<OpenStudio::Model::ThermalZone>] thermal zone array
  # @param coil [OpenStudio::Model::StraightComponent] heating coil
  # @return [Boolean] returns true if successful, false if not
  def model_set_central_preheat_coil_spm(model, thermal_zones, coil)
    return true
  end

  # Template method for evaluate DCV requirements in the user model
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model
  # @return [Boolean] returns true if successful, false if not
  def model_evaluate_dcv_requirements(model)
    return true
  end

  # Check whether the baseline model generation needs to run all four orientations
  # The default shall be true
  #
  # @param run_all_orients [Boolean] user inputs to indicate whether it is required to run all orientations
  # @param user_model [OpenStudio::Model::Model] OpenStudio model
  # @return [Boolean] return True if all orientation need to be run, False if not
  def run_all_orientations(run_all_orients, user_model)
    return run_all_orients
  end

  # Identify the return air type associated with each thermal zone
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @return [Boolean] returns true if successful, false if not
  def model_identify_return_air_type(model)
    # air-loop based system
    model.getThermalZones.each do |zone|
      # Conditioning category won't include indirectly conditioned thermal zones
      cond_cat = thermal_zone_conditioning_category(zone, OpenstudioStandards::Weather.model_get_climate_zone(model))

      # Initialize the return air type
      return_air_type = nil

      # The thermal zone is conditioned by zonal system
      if (cond_cat != 'Unconditioned') && zone.airLoopHVACs.empty?
        return_air_type = 'ducted_return_or_direct_to_unit'
      end

      # Assume that the primary heating and cooling (PHC) system
      # is last in the heating and cooling order (ignore DOAS)
      #
      # Get the heating and cooling PHC components
      heating_equipment = zone.equipmentInHeatingOrder[-1]
      cooling_equipment = zone.equipmentInCoolingOrder[-1]
      if heating_equipment.nil? && cooling_equipment.nil?
        next
      end

      unless heating_equipment.nil?
        if heating_equipment.to_ZoneHVACComponent.is_initialized
          heating_equipment_type = 'ZoneHVACComponent'
        elsif heating_equipment.to_StraightComponent.is_initialized
          heating_equipment_type = 'StraightComponent'
        end
      end
      unless cooling_equipment.nil?
        if cooling_equipment.to_ZoneHVACComponent.is_initialized
          cooling_equipment_type = 'ZoneHVACComponent'
        elsif cooling_equipment.to_StraightComponent.is_initialized
          cooling_equipment_type = 'StraightComponent'
        end
      end

      # Determine return configuration
      if (heating_equipment_type == 'ZoneHVACComponent') && (cooling_equipment_type == 'ZoneHVACComponent')
        return_air_type = 'ducted_return_or_direct_to_unit'
      else
        # Check heating air loop first
        if !heating_equipment.nil? && heating_equipment.to_StraightComponent.is_initialized
          air_loop = heating_equipment.to_StraightComponent.get.airLoopHVAC.get
          return_plenum = air_loop_hvac_return_air_plenum(air_loop)
          return_air_type = return_plenum.nil? ? 'ducted_return_or_direct_to_unit' : 'return_plenum'
          return_plenum = return_plenum.nil? ? nil : return_plenum.name.to_s
        end

        # Check cooling air loop second; Assume that return air plenum is the dominant case
        if !cooling_equipment.nil? &&
           (return_air_type != 'return_plenum') &&
           cooling_equipment.to_StraightComponent.is_initialized
          air_loop = cooling_equipment.to_StraightComponent.get.airLoopHVAC.get
          return_plenum = air_loop_hvac_return_air_plenum(air_loop)
          return_air_type = return_plenum.nil? ? 'ducted_return_or_direct_to_unit' : 'return_plenum'
          return_plenum = return_plenum.nil? ? nil : return_plenum.name.to_s
        end
      end

      # Catch all
      if return_air_type.nil?
        return_air_type = 'ducted_return_or_direct_to_unit'
      end

      # error if zone design air flow rate is not available
      if zone.model.version < OpenStudio::VersionString.new('3.6.0')
        OpenStudio.logFree(OpenStudio::Error, 'openstudio.Standards.Model', 'Required ThermalZone method .autosizedDesignAirFlowRate is not available in pre-OpenStudio 3.6.0 versions. Use a more recent version of OpenStudio.')
      end

      zone.additionalProperties.setFeature('return_air_type', return_air_type)
      zone.additionalProperties.setFeature('plenum', return_plenum) unless return_plenum.nil?
      zone.additionalProperties.setFeature('proposed_model_zone_design_air_flow', zone.autosizedDesignAirFlowRate.to_f)
    end
    return true
  end

  # Add reporting tolerances. Default values are based on the suggestions from the PRM-RM.
  #
  # @param model [OpenStudio::Model::Model] OpenStudio Model
  # @param heating_tolerance_deg_f [Double] Tolerance for time heating setpoint not met in degree F
  # @param cooling_tolerance_deg_f [Double] Tolerance for time cooling setpoint not met in degree F
  # @return [Boolean] returns true if successful, false if not
  def model_add_reporting_tolerances(model, heating_tolerance_deg_f: 1.0, cooling_tolerance_deg_f: 1.0)
    reporting_tolerances = model.getOutputControlReportingTolerances
    heating_tolerance_deg_c = OpenStudio.convert(heating_tolerance_deg_f, 'R', 'K').get
    cooling_tolerance_deg_c = OpenStudio.convert(cooling_tolerance_deg_f, 'R', 'K').get
    reporting_tolerances.setToleranceforTimeHeatingSetpointNotMet(heating_tolerance_deg_c)
    reporting_tolerances.setToleranceforTimeCoolingSetpointNotMet(cooling_tolerance_deg_c)

    true
  end

  # Update ground temperature profile based on the weather file specified in the model
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [Boolean] returns true if successful, false if not
  def model_update_ground_temperature_profile(model, climate_zone)
    true
  end
end

# Flag function to indicate whether the energy code uses space conditioning category.
# Default false; the 90.1 vintages that need it override this.
def has_space_conditioning_category
  false
end

