require_relative '../../../helpers/minitest_helper'

class TestHVACCreatorQuantities < Minitest::Test
  def setup
    @q = OpenstudioStandards::HVAC::Quantities
  end

  def test_resolve_temperature_ip
    assert_in_delta(82.22, @q.resolve({ supply_temp_f: 180.0 }, 'supply_temp', :temperature), 0.01)
  end

  def test_resolve_temperature_si
    assert_in_delta(82.0, @q.resolve({ supply_temp_c: 82.0 }, 'supply_temp', :temperature), 0.001)
  end

  def test_resolve_accepts_string_keys
    assert_in_delta(82.22, @q.resolve({ 'supply_temp_f' => 180.0 }, 'supply_temp', :temperature), 0.01)
  end

  def test_resolve_air_flow
    assert_in_delta(0.47195, @q.resolve({ max_airflow_cfm: 1000.0 }, 'max_airflow', :air_flow), 0.0001)
    assert_in_delta(0.5, @q.resolve({ max_airflow_m3s: 0.5 }, 'max_airflow', :air_flow), 0.0001)
  end

  def test_resolve_water_flow
    assert_in_delta(0.0063090, @q.resolve({ water_flow_gpm: 100.0 }, 'water_flow', :water_flow), 1.0e-6)
  end

  def test_resolve_capacity
    assert_in_delta(29307.1, @q.resolve({ capacity_btuh: 100_000.0 }, 'capacity', :capacity), 1.0)
  end

  def test_resolve_pressure
    assert_in_delta(249.089, @q.resolve({ pressure_rise_inh2o: 1.0 }, 'pressure_rise', :pressure), 0.1)
  end

  def test_resolve_pump_head
    assert_in_delta(179344.0, @q.resolve({ pump_head_fth2o: 60.0 }, 'pump_head', :pump_head), 50.0)
  end

  def test_resolve_enthalpy
    assert_in_delta(2326.0, @q.resolve({ econ_max_enth_btu_per_lb: 1.0 }, 'econ_max_enth', :enthalpy), 1.0)
  end

  def test_resolve_humidity_ratio_passthrough
    assert_in_delta(0.008, @q.resolve({ preheat_hr_kgpkg: 0.008 }, 'preheat_hr', :humidity_ratio), 1.0e-6)
  end

  def test_resolve_temperature_difference
    assert_in_delta(11.111, @q.resolve({ temp_delta_r: 20.0 }, 'temp_delta', :temperature_difference), 0.01)
  end

  def test_default_when_absent
    assert_nil(@q.resolve({}, 'supply_temp', :temperature))
    assert_equal(55.0, @q.resolve({}, 'supply_temp', :temperature, default: 55.0))
  end

  def test_both_units_agree
    # 180 F == 82.22 C, within tolerance
    assert_in_delta(82.22, @q.resolve({ supply_temp_f: 180.0, supply_temp_c: 82.22 }, 'supply_temp', :temperature), 0.01)
  end

  def test_conflicting_units_raise
    err = assert_raises(ArgumentError) do
      @q.resolve({ supply_temp_f: 180.0, supply_temp_c: 60.0 }, 'supply_temp', :temperature)
    end
    assert_match(/conflicting/, err.message)
  end

  def test_resolve_bang_raises_when_absent
    assert_raises(ArgumentError) { @q.resolve!({}, 'supply_temp', :temperature) }
  end

  def test_resolve_bang_returns_value
    assert_in_delta(82.22, @q.resolve!({ supply_temp_f: 180.0 }, 'supply_temp', :temperature), 0.01)
  end

  def test_unknown_dimension_raises
    assert_raises(ArgumentError) { @q.resolve({}, 'foo', :not_a_dimension) }
  end

  def test_convert_identity_and_nil_units
    assert_equal(5.0, @q.convert(5.0, nil, 'W'))
    assert_equal(5.0, @q.convert(5.0, 'W', 'W'))
  end
end
