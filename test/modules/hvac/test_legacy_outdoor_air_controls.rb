require_relative '../../helpers/minitest_helper'

# Outdoor air controls the DOE Ref templates give older systems: a fixed minimum damper whose
# outdoor air follows the VAV supply flow, and VAV terminals left at their 30% minimum where
# ventilation is occupant driven. A newer template (set_hvac_template after an HVAC replacement)
# restores what the DOE Ref template changed. Packaged unit fans stay continuous on every template;
# a template that cycles them overrides air_loop_hvac_unitary_supply_fan_cycles?.
class TestLegacyOutdoorAirControls < Minitest::Test
  def setup
    @doe_ref = Standard.build('ComStock DOE Ref 1980-2004')
    @doe_ref_pre_1980 = Standard.build('ComStock DOE Ref Pre-1980')
    @std = Standard.build('ComStock 90.1-2013')
  end

  def build_zones(model, count)
    (0...count).map do |i|
      polygon = OpenStudio::Point3dVector.new
      [[0, 0], [0, 10], [10, 10], [10, 0]].each { |x, y| polygon << OpenStudio::Point3d.new(x + (i * 20), y, 0) }
      space = OpenStudio::Model::Space.fromFloorPrint(polygon, 3.0, model).get
      space.setName("Space #{i}")
      zone = OpenStudio::Model::ThermalZone.new(model)
      zone.setName("Zone #{i}")
      space.setThermalZone(zone)
      zone
    end
  end

  def set_outdoor_air(zone, per_person: 0.0, per_area: 0.0, ach: 0.0)
    space = zone.spaces.first
    dsoa = OpenStudio::Model::DesignSpecificationOutdoorAir.new(space.model)
    dsoa.setOutdoorAirMethod('Sum')
    dsoa.setOutdoorAirFlowperPerson(per_person)
    dsoa.setOutdoorAirFlowperFloorArea(per_area)
    dsoa.setOutdoorAirFlowAirChangesperHour(ach)
    space.setDesignSpecificationOutdoorAir(dsoa)
  end

  def controller_oa(air_loop)
    air_loop.airLoopHVACOutdoorAirSystem.get.getControllerOutdoorAir
  end

  def unitary_of(air_loop)
    air_loop.supplyComponents.map(&:to_AirLoopHVACUnitarySystem).find(&:is_initialized).get
  end

  def terminal_of(zone)
    zone.airLoopHVACTerminal.get.to_AirTerminalSingleDuctVAVReheat.get
  end

  def test_doe_ref_vav_outdoor_air_is_a_fixed_damper_fraction_and_a_newer_template_restores_it
    model = OpenStudio::Model::Model.new
    loop = @std.model_add_pvav(model, build_zones(model, 3), electric_reheat: true)
    assert_equal('FixedMinimum', controller_oa(loop).getMinimumLimitType)

    @doe_ref.air_loop_hvac_apply_minimum_outdoor_air_control(loop)
    assert_equal('ProportionalMinimum', controller_oa(loop).getMinimumLimitType)
    assert_equal(model.alwaysOffDiscreteSchedule, controller_oa(loop).controllerMechanicalVentilation.availabilitySchedule)

    @std.air_loop_hvac_apply_minimum_outdoor_air_control(loop)
    assert_equal('FixedMinimum', controller_oa(loop).getMinimumLimitType)
    assert_equal(model.alwaysOnDiscreteSchedule, controller_oa(loop).controllerMechanicalVentilation.availabilitySchedule)
  end

  def test_single_zone_systems_keep_their_outdoor_air_control
    model = OpenStudio::Model::Model.new
    loop = @std.model_add_psz_ac(model, build_zones(model, 1)).first
    @doe_ref_pre_1980.air_loop_hvac_apply_minimum_outdoor_air_control(loop)
    assert_equal('FixedMinimum', controller_oa(loop).getMinimumLimitType)
    assert_equal(model.alwaysOnDiscreteSchedule, controller_oa(loop).controllerMechanicalVentilation.availabilitySchedule)
  end

  def test_doe_ref_packaged_fans_stay_continuous
    model = OpenStudio::Model::Model.new
    loop = @std.model_add_psz_ac(model, build_zones(model, 1)).first
    unitary = unitary_of(loop)
    continuous = unitary.supplyAirFanOperatingModeSchedule.get
    refute_equal(model.alwaysOffDiscreteSchedule, continuous)

    [@doe_ref, @doe_ref_pre_1980].each do |std|
      refute(std.air_loop_hvac_unitary_supply_fan_cycles?(loop))
      std.air_loop_hvac_apply_unitary_supply_fan_operating_mode(loop)
      assert_equal(continuous, unitary.supplyAirFanOperatingModeSchedule.get)
      refute(unitary.additionalProperties.hasFeature('continuous_fan_operating_mode_schedule'))
    end
  end

  def test_a_cycling_template_records_the_continuous_schedule_and_a_newer_template_restores_it
    model = OpenStudio::Model::Model.new
    loop = @std.model_add_psz_ac(model, build_zones(model, 1)).first
    unitary = unitary_of(loop)
    continuous = unitary.supplyAirFanOperatingModeSchedule.get
    cycling = Standard.build('ComStock DOE Ref 1980-2004')
    cycling.define_singleton_method(:air_loop_hvac_unitary_supply_fan_cycles?) { |_air_loop_hvac| true }

    cycling.air_loop_hvac_apply_unitary_supply_fan_operating_mode(loop)
    assert_equal(model.alwaysOffDiscreteSchedule, unitary.supplyAirFanOperatingModeSchedule.get)
    assert(unitary.additionalProperties.hasFeature('continuous_fan_operating_mode_schedule'))

    # applying the cycling template again keeps the recorded continuous schedule
    cycling.air_loop_hvac_apply_unitary_supply_fan_operating_mode(loop)
    assert_equal(continuous.name.to_s, unitary.additionalProperties.getFeatureAsString('continuous_fan_operating_mode_schedule').get)

    @std.air_loop_hvac_apply_unitary_supply_fan_operating_mode(loop)
    assert_equal(continuous, unitary.supplyAirFanOperatingModeSchedule.get)
    refute(unitary.additionalProperties.hasFeature('continuous_fan_operating_mode_schedule'))
  end

  def test_a_newer_template_leaves_untagged_cycling_fans_alone
    model = OpenStudio::Model::Model.new
    loop = @std.model_add_psz_ac(model, build_zones(model, 1), fan_type: 'Cycling').first
    @std.air_loop_hvac_apply_unitary_supply_fan_operating_mode(loop)
    assert_equal(model.alwaysOffDiscreteSchedule, unitary_of(loop).supplyAirFanOperatingModeSchedule.get)
  end

  def test_doe_ref_terminals_keep_their_minimum_where_ventilation_is_occupant_driven
    model = OpenStudio::Model::Model.new
    zones = build_zones(model, 3)
    set_outdoor_air(zones[0], per_person: 0.00708) # classroom: per person only
    set_outdoor_air(zones[1], ach: 6.0)            # health care room: air changes
    set_outdoor_air(zones[2], per_area: 0.0071)    # laboratory: floor area only (1.4 cfm/ft2)
    zones[0].spaces.first.setPeoplePerFloorArea(0.538) # 50 ppl/1000 ft2: 0.38 m3/s of outdoor air
    loop = @doe_ref.model_add_pvav(model, zones, electric_reheat: true)
    zones.each { |zone| terminal_of(zone).setMaximumAirFlowRate(1.0) }
    before = terminal_of(zones[0]).constantMinimumAirFlowFraction.get

    refute(@doe_ref.air_loop_hvac_vav_terminal_minimum_covers_zone_outdoor_air?(loop, zones[0]))
    assert(@doe_ref.air_loop_hvac_vav_terminal_minimum_covers_zone_outdoor_air?(loop, zones[1]))
    assert(@doe_ref.air_loop_hvac_vav_terminal_minimum_covers_zone_outdoor_air?(loop, zones[2]))

    assert_equal(2, @doe_ref.air_loop_hvac_apply_vav_terminal_minimum_outdoor_air(loop))
    assert_in_delta(before, terminal_of(zones[0]).constantMinimumAirFlowFraction.get, 1e-9)
    assert_in_delta(0.5, terminal_of(zones[1]).constantMinimumAirFlowFraction.get, 1e-6)
    assert_in_delta(0.71, terminal_of(zones[2]).constantMinimumAirFlowFraction.get, 1e-6)

    # a newer template raises the occupant-driven zone too
    assert_equal(1, @std.air_loop_hvac_apply_vav_terminal_minimum_outdoor_air(loop))
    assert_operator(terminal_of(zones[0]).constantMinimumAirFlowFraction.get, :>, before)
  end

  # The DOE Ref and 90.1-2004 templates carry the R3 prototype rates: classrooms at ASHRAE 62-1999's
  # 8 L/s (16.95 cfm) per person and the prototype school's 23.22 (DOE Ref) or 25 (90.1-2004)
  # ppl/1000 ft2.
  def test_doe_ref_and_90_1_2004_classrooms_carry_the_r3_prototype_rates
    root = File.join(File.dirname(__FILE__), '../../../lib/openstudio-standards')
    vent = JSON.parse(File.read(File.join(root, 'ventilation/data/ventilation_space_type_data.json')), symbolize_names: true)[:classroom_lecture_training_ventilation]
    occ = JSON.parse(File.read(File.join(root, 'occupancy/data/typical_space_type_occupancy.json')), symbolize_names: true)[:classroom_lecture_training_ventilation]
    { 'ComStock DOE Ref Pre-1980' => 23.22, 'DOE Ref Pre-1980' => 23.22, 'ComStock DOE Ref 1980-2004' => 23.22,
      'DOE Ref 1980-2004' => 23.22, 'ComStock 90.1-2004' => 25.0, '90.1-2004' => 25.0 }.each do |template, density|
      entry = OpenstudioStandards::Ventilation.template_entry(vent, template)
      assert_in_delta(16.95, entry[:ventilation_per_person], 1e-9, template)
      assert_in_delta(0.0, entry[:ventilation_per_area], 1e-9, template)
      assert_match(%r{ASHRAE 62-1999 Table 2 rate in SI \(8 L/s per person}, entry[:source], template)
      assert_in_delta(density, OpenstudioStandards::Ventilation.template_entry(occ, template)[:occupancy_per_area], 1e-9, template)
    end
  end
end
