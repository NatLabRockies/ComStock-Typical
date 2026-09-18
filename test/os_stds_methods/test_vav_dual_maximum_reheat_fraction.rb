require_relative '../helpers/minitest_helper'

# Dual-maximum (ReverseWithLimits) VAV terminals: the maximum flow fraction during reheat is
# 50% of the cooling maximum unless the zone's heating design airflow is larger. EnergyPlus
# 25.1 sizes the reheat coil on the reheat airflow, and a heating-dominated zone held at 50%
# fails UA autosizing with a fatal (NREL/EnergyPlus#11078): the 2026-09 Kestrel run lost
# eleven warehouses that way, on fine-storage zones whose heating design flow was up to 2x
# their cooling flow.
class TestVAVDualMaximumReheatFraction < Minitest::Test
  def setup
    @std = Standard.build('90.1-2013')
  end

  def make_terminal(model)
    sch = model.alwaysOnDiscreteSchedule
    coil = OpenStudio::Model::CoilHeatingWater.new(model, sch)
    OpenStudio::Model::AirTerminalSingleDuctVAVReheat.new(model, sch, coil)
  end

  def test_cooling_dominated_zones_keep_the_fifty_percent_rule
    # heating flow at or below half the maximum: the 90.1 cap stands
    assert_in_delta(0.5, @std.air_terminal_single_duct_vav_reheat_dual_maximum_reheat_fraction(0.372, 0.758), 1e-6)
    assert_in_delta(0.5, @std.air_terminal_single_duct_vav_reheat_dual_maximum_reheat_fraction(0.5, 1.0), 1e-6)
  end

  def test_heating_dominated_zones_get_their_heating_design_flow
    # warehouse 416 zone A: 0.449 m3/s heating against a 0.449 m3/s maximum
    assert_in_delta(1.0, @std.air_terminal_single_duct_vav_reheat_dual_maximum_reheat_fraction(0.449, 0.449), 1e-6)
    # warehouse 2010 zone C: 0.370 m3/s heating, 0.370 maximum, which the pinned 0.5 halved
    assert_in_delta(1.0, @std.air_terminal_single_duct_vav_reheat_dual_maximum_reheat_fraction(0.370, 0.370), 1e-6)
    # between the two: the fraction is the heating flow over the maximum
    assert_in_delta(0.75, @std.air_terminal_single_duct_vav_reheat_dual_maximum_reheat_fraction(0.75, 1.0), 1e-6)
  end

  def test_the_fraction_never_exceeds_one
    assert_in_delta(1.0, @std.air_terminal_single_duct_vav_reheat_dual_maximum_reheat_fraction(1.4, 1.0), 1e-6)
  end

  def test_missing_sizing_data_falls_back_to_the_default
    assert_in_delta(0.5, @std.air_terminal_single_duct_vav_reheat_dual_maximum_reheat_fraction(nil, 1.0), 1e-6)
    assert_in_delta(0.5, @std.air_terminal_single_duct_vav_reheat_dual_maximum_reheat_fraction(0.8, nil), 1e-6)
    assert_in_delta(0.5, @std.air_terminal_single_duct_vav_reheat_dual_maximum_reheat_fraction(0.8, 0.0), 1e-6)
  end

  def test_a_different_default_is_honored
    assert_in_delta(0.6, @std.air_terminal_single_duct_vav_reheat_dual_maximum_reheat_fraction(0.3, 1.0, 0.6), 1e-6)
    assert_in_delta(0.7, @std.air_terminal_single_duct_vav_reheat_dual_maximum_reheat_fraction(0.7, 1.0, 0.6), 1e-6)
  end

  # Without a sizing run the zone heating design flow is unknown: the terminal gets the
  # default and the model still translates, rather than an exception or a blank field.
  def test_terminal_without_sizing_data_is_set_to_the_default
    model = OpenStudio::Model::Model.new
    terminal = make_terminal(model)
    terminal.setMaximumAirFlowRate(1.0)
    zone = OpenStudio::Model::ThermalZone.new(model)
    loop = OpenStudio::Model::AirLoopHVAC.new(model)
    loop.addBranchForZone(zone, terminal.to_StraightComponent)

    applied = @std.air_terminal_single_duct_vav_reheat_apply_dual_maximum_reheat_fraction(terminal, zone)
    assert_in_delta(0.5, applied, 1e-6)
    assert(terminal.maximumFlowFractionDuringReheat.is_initialized)
    assert_in_delta(0.5, terminal.maximumFlowFractionDuringReheat.get, 1e-6)
  end

  # The damper action pass on a dual-maximum template reaches the terminal through its zone:
  # ReverseWithLimits with a hot water coil, and the fraction set (to the default here, with no
  # sizing run to read).
  def test_damper_action_sets_reverse_with_limits_and_a_fraction_on_hot_water_reheat
    model = OpenStudio::Model::Model.new
    terminal = make_terminal(model)
    terminal.setMaximumAirFlowRate(1.0)
    zone = OpenStudio::Model::ThermalZone.new(model)
    loop = OpenStudio::Model::AirLoopHVAC.new(model)
    loop.addBranchForZone(zone, terminal.to_StraightComponent)

    assert_equal('Dual Maximum', @std.air_loop_hvac_vav_damper_action(loop))
    @std.air_loop_hvac_apply_vav_damper_action(loop)
    assert_equal('ReverseWithLimits', terminal.damperHeatingAction)
    assert_in_delta(0.5, terminal.maximumFlowFractionDuringReheat.get, 1e-6)
  end

  # Electric reheat is single maximum whatever the template: untouched by the fraction logic.
  def test_electric_reheat_stays_normal
    model = OpenStudio::Model::Model.new
    sch = model.alwaysOnDiscreteSchedule
    terminal = OpenStudio::Model::AirTerminalSingleDuctVAVReheat.new(model, sch, OpenStudio::Model::CoilHeatingElectric.new(model, sch))
    zone = OpenStudio::Model::ThermalZone.new(model)
    loop = OpenStudio::Model::AirLoopHVAC.new(model)
    loop.addBranchForZone(zone, terminal.to_StraightComponent)

    @std.air_loop_hvac_apply_vav_damper_action(loop)
    assert_equal('Normal', terminal.damperHeatingAction)
  end
end
