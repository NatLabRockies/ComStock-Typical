require_relative '../helpers/minitest_helper'

class TestMisc < Minitest::Test
  # The create_model helper and the commented-out test_plenum_space_conditioning that used
  # it were built on model_create_prototype_model, which went with the prototype buildings
  # in Phase 3. test_add_table_lookup_curve went too: it built Standard.build('ECMS'),
  # and ECMS is part of NECB, removed in Phase 1.

  def test_add_material
    model = OpenStudio::Model::Model.new
    std = Standard.build('90.1-2019')

    # Complete definition
    mat_1 = std.model_add_material(model, 'Simple Glazing U 0.1 SHGC 0.2 VT 0.3')
    assert(mat_1.uFactor.round(2) == OpenStudio.convert(0.1, 'Btu/hr*ft^2*R', 'W/m^2*K').get.round(2))
    assert(mat_1.solarHeatGainCoefficient == 0.2)
    assert(mat_1.visibleTransmittance.get == 0.3)

    # Missing information
    mat_2 = std.model_add_material(model, 'U 0.51 SHGC 0.23 Simple Glazing')
    assert(mat_2.uFactor.round(2) == OpenStudio.convert(0.51, 'Btu/hr*ft^2*R', 'W/m^2*K').get.round(2))
    assert(mat_2.solarHeatGainCoefficient == 0.23)
    assert(mat_2.visibleTransmittance.get == 0.81)

    # Missing info so look in library; expected to return an optional material since it is not in the library
    mat_3 = std.model_add_material(model, 'U 0.51 SHGC 0.23 Simp G Window')
    assert(mat_3.is_a?(OpenStudio::Model::OptionalMaterial))
  end
end
