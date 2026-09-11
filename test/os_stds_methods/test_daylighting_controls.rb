require_relative '../helpers/minitest_helper'

class TestDaylightingControls < Minitest::Test
  # test_remove_daylighting_controls went with the Appendix G PRM machinery in Phase 2:
  # it called space_set_baseline_daylighting_controls against a model under
  # test/90_1_prm/models, and both the method and the model are gone.

  def test_add_space_daylighting_controls
    std = Standard.build('90.1-2019')
    model = std.safe_load_model("#{File.dirname(__FILE__)}/models/test_school.osm")

    model.getSpaces.each do |space|
      std.space_add_daylighting_controls(space, true)
    end
  end
end
