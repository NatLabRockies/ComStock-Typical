require_relative '../helpers/minitest_helper'

# The rated sensible heat ratio of a single speed DX cooling coil is capped where EnergyPlus
# could not solve the coil bypass factor. Outpatient 87527 in the 2026-09 100k run had a
# 7 kBtu/h storage-room coil autosized to a ratio of 0.796 at 2,119 W and 0.111 m3/s; the
# rated outlet air sat on the saturation curve and the hardsize sizing run died on
# "negative coil bypass factor".
class TestDxCoilRatedShrCap < Minitest::Test
  def setup
    @std = Standard.build('90.1-2013')
  end

  # the coil that failed, the same coil one sizing run earlier (which passed, barely), and
  # ordinary coils at EnergyPlus's own correlation ratio 0.431 + 6086 x flow per capacity
  FAILED = [2119.19, 0.11124, 0.796].freeze
  EARLIER = [1970.25, 0.0987397, 0.777].freeze
  ORDINARY = [[10_000.0, 0.45, 0.700], [10_000.0, 0.40, 0.669], [10_000.0, 0.60, 0.791], [30_000.0, 1.5, 0.730]].freeze

  def test_the_failing_coil_has_no_bypass_factor_to_speak_of
    cbf = @std.coil_cooling_dx_single_speed_rated_bypass_factor(*FAILED)
    assert_operator(cbf, :<, 0.01, 'the rated outlet is on the saturation curve')
    assert_operator(@std.coil_cooling_dx_single_speed_rated_bypass_factor(*EARLIER), :<, 0.01)
  end

  def test_ordinary_coils_have_a_healthy_bypass_factor_and_are_not_capped
    ORDINARY.each do |capacity, flow, shr|
      cbf = @std.coil_cooling_dx_single_speed_rated_bypass_factor(capacity, flow, shr)
      assert_operator(cbf, :>=, 0.08, "#{capacity} W at #{flow} m3/s, ratio #{shr}")
      assert_in_delta(shr, @std.coil_cooling_dx_single_speed_feasible_rated_shr(capacity, flow, shr), 1e-9)
    end
  end

  def test_the_cap_lowers_the_ratio_until_the_bypass_factor_clears_the_floor
    capacity, flow, shr = FAILED
    capped = @std.coil_cooling_dx_single_speed_feasible_rated_shr(capacity, flow, shr)
    assert_operator(capped, :<, shr)
    assert_operator(capped, :>, 0.7, 'a few hundredths is all it takes')
    assert_operator(@std.coil_cooling_dx_single_speed_rated_bypass_factor(capacity, flow, capped), :>=, 0.1)
    # one step back up would not clear the floor: the cap is the largest ratio that does
    assert_operator(@std.coil_cooling_dx_single_speed_rated_bypass_factor(capacity, flow, capped + 0.005), :<, 0.1)
  end

  def test_the_cap_survives_the_drift_between_sizing_runs
    # capped on the earlier sizing run's values, the ratio still clears the floor on the later run's
    capped = @std.coil_cooling_dx_single_speed_feasible_rated_shr(*EARLIER)
    assert_operator(@std.coil_cooling_dx_single_speed_rated_bypass_factor(FAILED[0], FAILED[1], capped), :>, 0.0)
  end

  def test_nonsense_inputs_give_nil_and_leave_the_ratio_alone
    assert_nil(@std.coil_cooling_dx_single_speed_rated_bypass_factor(0.0, 0.1, 0.75))
    assert_nil(@std.coil_cooling_dx_single_speed_rated_bypass_factor(1000.0, 0.0, 0.75))
    assert_in_delta(0.75, @std.coil_cooling_dx_single_speed_feasible_rated_shr(0.0, 0.1, 0.75), 1e-9)
  end

  def test_apply_sets_the_ratio_on_a_sized_coil_and_skips_an_unsized_one
    model = OpenStudio::Model::Model.new
    coil = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
    # nothing sized and no sizing run: left alone
    assert_nil(@std.coil_cooling_dx_single_speed_apply_rated_shr_cap(coil))
    assert(coil.isRatedSensibleHeatRatioAutosized)

    coil.setRatedTotalCoolingCapacity(FAILED[0])
    coil.setRatedAirFlowRate(FAILED[1])
    coil.setRatedSensibleHeatRatio(FAILED[2])
    capped = @std.coil_cooling_dx_single_speed_apply_rated_shr_cap(coil)
    refute_nil(capped)
    assert_in_delta(capped, coil.ratedSensibleHeatRatio.get, 1e-9)
    assert_operator(coil.ratedSensibleHeatRatio.get, :<, FAILED[2])

    # already fine: untouched
    fine = OpenStudio::Model::CoilCoolingDXSingleSpeed.new(model)
    fine.setRatedTotalCoolingCapacity(10_000.0)
    fine.setRatedAirFlowRate(0.45)
    fine.setRatedSensibleHeatRatio(0.7)
    assert_nil(@std.coil_cooling_dx_single_speed_apply_rated_shr_cap(fine))
    assert_in_delta(0.7, fine.ratedSensibleHeatRatio.get, 1e-9)
  end
end
