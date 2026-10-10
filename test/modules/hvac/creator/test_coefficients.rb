require_relative '../../../helpers/minitest_helper'

class TestHVACCreatorCoefficients < Minitest::Test
  def setup
    @model = OpenStudio::Model::Model.new
    @ctx = OpenstudioStandards::HVAC::BuildContext.new(@model)
    @coef = OpenstudioStandards::HVAC::Coefficients
    @factory = OpenstudioStandards::HVAC::ComponentFactory
  end

  def test_build_user_biquadratic
    curve = @coef.build_user_curve(@ctx, { type: 'Biquadratic',
                                           coefficients: [0.1, 0.2, 0.3, 0.4, 0.5, 0.6],
                                           min_x: 10.0, max_x: 40.0, min_y: 5.0, max_y: 25.0, name: 'CapFT' })
    bq = curve.to_CurveBiquadratic.get
    assert_equal('CapFT', bq.name.get)
    assert_in_delta(0.1, bq.coefficient1Constant, 1e-9)
    assert_in_delta(0.6, bq.coefficient6xTIMESY, 1e-9)
    assert_in_delta(10.0, bq.minimumValueofx, 1e-9)
    assert_in_delta(25.0, bq.maximumValueofy, 1e-9)
  end

  def test_build_user_quadratic
    curve = @coef.build_user_curve(@ctx, { type: 'Quadratic', coefficients: [0.8, 0.2, 0.0] })
    q = curve.to_CurveQuadratic.get
    assert_in_delta(0.8, q.coefficient1Constant, 1e-9)
    assert_in_delta(0.2, q.coefficient2x, 1e-9)
  end

  def test_build_user_cubic
    curve = @coef.build_user_curve(@ctx, { type: 'Cubic', coefficients: [0.1, 0.2, 0.3, 0.4] })
    assert(curve.to_CurveCubic.is_initialized)
    assert_in_delta(0.4, curve.to_CurveCubic.get.coefficient4xPOW3, 1e-9)
  end

  def test_build_user_bicubic
    curve = @coef.build_user_curve(@ctx, { type: 'Bicubic', coefficients: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] })
    assert(curve.to_CurveBicubic.is_initialized)
  end

  def test_build_user_exponent
    curve = @coef.build_user_curve(@ctx, { type: 'Exponent', coefficients: [0.0, 1.0, 3.0] })
    assert(curve.to_CurveExponent.is_initialized)
  end

  def test_unknown_type_raises
    assert_raises(ArgumentError) { @coef.build_user_curve(@ctx, { type: 'Wat', coefficients: [1] }) }
  end

  def test_missing_coefficients_raises
    assert_raises(ArgumentError) { @coef.build_user_curve(@ctx, { type: 'Quadratic' }) }
  end

  def test_resolve_curve_hash_builds_user_curve
    curve = @coef.resolve_curve(@ctx, { type: 'Quadratic', coefficients: [1.0, 0.0, 0.0] })
    assert(curve.to_CurveQuadratic.is_initialized)
  end

  def test_resolve_curve_named_string_looks_up_model
    existing = OpenStudio::Model::CurveBiquadratic.new(@model)
    existing.setName('NamedCurve')
    resolved = @coef.resolve_curve(@ctx, 'NamedCurve')
    assert_equal('NamedCurve', resolved.name.get)
  end

  def test_resolve_curve_source_key_pair_looks_up_model
    existing = OpenStudio::Model::CurveBiquadratic.new(@model)
    existing.setName('LibKey')
    resolved = @coef.resolve_curve(@ctx, ['SomeSource', 'LibKey'])
    assert_equal('LibKey', resolved.name.get)
  end

  def test_context_curve_dispatches_hash
    curve = @ctx.curve({ type: 'Cubic', coefficients: [0.0, 1.0, 0.0, 0.0] })
    assert(curve.to_CurveCubic.is_initialized)
  end

  # end-to-end: a DX single speed coil with a user-entered cap_ft curve override
  def test_dx_coil_user_cap_ft_curve
    coil = @factory.build({ obj_type: 'CoilCoolingDXSingleSpeed', rated_cop: 3.5,
                            cap_ft: { type: 'Biquadratic', coefficients: [0.5, 0.01, 0.0, 0.02, 0.0, 0.0], name: 'MyCapFT' } }, @ctx)
    dx = coil.to_CoilCoolingDXSingleSpeed.get
    applied = dx.totalCoolingCapacityFunctionOfTemperatureCurve.to_CurveBiquadratic.get
    assert_equal('MyCapFT', applied.name.get)
    assert_in_delta(0.5, applied.coefficient1Constant, 1e-9)
  end

  # end-to-end: a DX coil referencing a named curve already in the model
  def test_dx_coil_named_cap_ft_curve
    named = OpenStudio::Model::CurveBiquadratic.new(@model)
    named.setName('SharedCapFT')
    coil = @factory.build({ obj_type: 'CoilCoolingDXSingleSpeed', cap_ft: 'SharedCapFT' }, @ctx)
    dx = coil.to_CoilCoolingDXSingleSpeed.get
    assert_equal('SharedCapFT', dx.totalCoolingCapacityFunctionOfTemperatureCurve.name.get)
  end
end
