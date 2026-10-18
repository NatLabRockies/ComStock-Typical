require_relative '../helpers/minitest_helper'

# Coverage for fan_standard_minimum_motor_efficiency_and_size.
#
# This method had no test, which is why a silent regression shipped: upstream commit fddbdc9
# (PR #1716) removed a second lookup step that the DOE Ref motors tables had been authored
# around. A 0.29 "PSC motors below 1 HP" row that the second step always skipped became
# reachable, and every sub-1-HP DOE Ref fan dropped from 0.825 to 0.29 motor efficiency --
# a 2.845x jump in fan power that reached published results.
class TestFanMotorEfficiency < Minitest::Test
  # A supply fan on an air loop is not a "small fan", so it takes the motors table lookup
  # rather than the fractional-horsepower path.
  def supply_fan(model)
    air_loop = OpenStudio::Model::AirLoopHVAC.new(model)
    fan = OpenStudio::Model::FanOnOff.new(model)
    fan.addToNode(air_loop.supplyOutletNode)
    fan
  end

  def motor_eff(template, bhp)
    standard = Standard.build(template)
    model = OpenStudio::Model::Model.new
    standard.fan_standard_minimum_motor_efficiency_and_size(supply_fan(model), bhp).first
  end

  # The regression itself. A half-horsepower supply fan in a DOE Ref template must get the
  # 90.1-2004 Table 10.8 value, not the 0.29 fractional-motor value.
  def test_sub_one_hp_doe_ref_is_not_the_fractional_motor_value
    ['DOE Ref 1980-2004', 'DOE Ref Pre-1980'].each do |template|
      eff = motor_eff(template, 0.4)
      assert_in_delta(0.825, eff, 0.001,
                      "#{template} at 0.4 bhp should be 0.825; got #{eff}. " \
                      'A value near 0.29 means the fractional-motor row is reachable again.')
    end
  end

  # Guard the other direction: restoring the old two-step round-up would fix DOE Ref by
  # over-crediting 90.1, whose tables are not offset. 0.4 bhp must stay at 0.825, not 0.840.
  def test_sub_one_hp_ashrae_is_unchanged
    eff = motor_eff('90.1-2004', 0.4)
    assert_in_delta(0.825, eff, 0.001,
                    "90.1-2004 at 0.4 bhp should be 0.825; got #{eff}. " \
                    '0.840 means a round-up step was reintroduced.')
  end

  # DOE Ref and 90.1-2004 should now agree away from bin edges, since the DOE Ref rows carry
  # 90.1-2004 Table 10.8 values.
  def test_doe_ref_matches_ashrae_away_from_bin_edges
    [0.4, 1.2, 1.8, 2.5, 6.0, 12.0].each do |bhp|
      assert_in_delta(motor_eff('90.1-2004', bhp), motor_eff('DOE Ref 1980-2004', bhp), 0.001,
                      "DOE Ref and 90.1-2004 disagree at #{bhp} bhp")
    end
  end

  # The structural guard. No motors table should return an efficiency low enough to be a
  # fractional-motor value for a fan large enough to be a real supply fan. This is what would
  # have caught the original regression in any template, not just the two known ones.
  def test_no_template_returns_a_fractional_motor_efficiency_for_a_real_fan
    templates = ['DOE Ref Pre-1980', 'DOE Ref 1980-2004',
                 '90.1-2004', '90.1-2007', '90.1-2010', '90.1-2013',
                 'DEER Pre-1975', 'DEER 1985', 'DEER 2003', 'DEER 2017']
    templates.each do |template|
      [0.2, 0.5, 0.9, 2.0, 10.0].each do |bhp|
        eff = motor_eff(template, bhp)
        assert(eff > 0.5,
               "#{template} returned motor efficiency #{eff} at #{bhp} bhp. " \
               'Values below 0.5 belong to fractional/shaded-pole motors and should not be ' \
               'reachable for a supply fan.')
      end
    end
  end

  # Nominal size is the matched row's maximum_capacity, rounded to a whole number at or above
  # 2 HP. For 90.1-2010, 6.3 bhp matches the 5.001-7.500 row, so 7.5 is reported as 8.
  def test_nominal_size_is_the_matched_bin
    standard = Standard.build('90.1-2010')
    model = OpenStudio::Model::Model.new
    eff, nominal_hp = standard.fan_standard_minimum_motor_efficiency_and_size(supply_fan(model), 6.3)
    assert_in_delta(8.0, nominal_hp, 0.01,
                    '6.3 bhp matches the 5.001-7.500 row; 7.5 rounds to a nominal 8 HP')
    # 90.1 rows are date-effective and the lookup passes Date.today: this bin is 0.895 before
    # 2010-12-19 and 0.917 after.
    assert_in_delta(0.917, eff, 0.001, '90.1-2010 at 6.3 bhp should be 0.917 under a current date')
  end

  # Below 2 HP the nominal size keeps one decimal rather than rounding to a whole number.
  def test_nominal_size_keeps_a_decimal_below_two_hp
    standard = Standard.build('DOE Ref 1980-2004')
    model = OpenStudio::Model::Model.new
    _eff, nominal_hp = standard.fan_standard_minimum_motor_efficiency_and_size(supply_fan(model), 0.4)
    assert_in_delta(1.0, nominal_hp, 0.01, '0.4 bhp matches the 0.000-0.999 row, nominal 1.0 HP')
  end

  # Zero-airflow systems (elevator shafts, heated-only spaces) must not hit the table.
  def test_zero_bhp_returns_the_default
    standard = Standard.build('DOE Ref 1980-2004')
    model = OpenStudio::Model::Model.new
    eff, nominal_hp = standard.fan_standard_minimum_motor_efficiency_and_size(supply_fan(model), 0.0)
    assert_in_delta(0.85, eff, 0.001)
    assert_in_delta(0.0, nominal_hp, 0.001)
  end
end
