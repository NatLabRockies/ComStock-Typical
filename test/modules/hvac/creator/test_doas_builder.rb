require_relative '../../../helpers/minitest_helper'

class TestHVACCreatorDoasBuilder < Minitest::Test
  def setup
    @model = OpenStudio::Model::Model.new
    @ctx = OpenstudioStandards::HVAC::BuildContext.new(@model)
    @air = OpenstudioStandards::HVAC::AirLoopBuilder
    @doas = OpenstudioStandards::HVAC::DoasBuilder
    served_loops(['AHU 1', 'AHU 2'])
  end

  def served_loops(names)
    names.each do |n|
      @air.build({
        name: n,
        supply_components: [{ obj_type: 'FanConstantVolume', name: "#{n} Fan" }],
        oa_control: { ventilation: { min_oa_flow_cfm: 100.0 } },
        controls: [{ spm_type: 'Scheduled', spm_temp_f: 55.0 }]
      }, @ctx)
    end
  end

  def doas_spec
    {
      name: 'DOAS',
      air_loops: ['AHU 1', 'AHU 2'],
      preheat_des_t_f: 45.0, precool_des_t_f: 60.0,
      components: [
        { obj_type: 'CoilHeatingElectric', name: 'DOAS Preheat' },
        { obj_type: 'CoilHeatingElectric', name: 'DOAS Reheat' }
      ],
      controls: [{ spm_type: 'Scheduled', spm_temp_f: 65.0 }]
    }
  end

  def test_builds_dedicated_oa_system
    doas = @doas.build(doas_spec, @ctx)
    assert(doas.to_AirLoopHVACDedicatedOutdoorAirSystem.is_initialized)
    assert_equal('DOAS', doas.name.get)
    assert_equal(2, doas.numberofAirLoops)
  end

  def test_design_conditions
    doas = @doas.build(doas_spec, @ctx)
    assert_in_delta(7.22, doas.preheatDesignTemperature, 0.05)
    assert_in_delta(15.56, doas.precoolDesignTemperature, 0.05)
  end

  def test_components_on_oa_stream
    doas = @doas.build(doas_spec, @ctx)
    coils = doas.airLoopHVACOutdoorAirSystem.oaComponents.select { |c| c.to_CoilHeatingElectric.is_initialized }
    assert_equal(2, coils.size)
  end

  def test_control_spm_on_inboard_component_outlet
    doas = @doas.build(doas_spec, @ctx)
    # inboard-most component is the last listed (DOAS Reheat); its outlet feeds the served loops
    reheat = @model.getCoilHeatingElectrics.find { |c| c.name.get == 'DOAS Reheat' }
    outlet_node = reheat.outletModelObject.get.to_Node.get
    managers = outlet_node.setpointManagers.select { |m| m.to_SetpointManagerScheduled.is_initialized }
    assert_equal(1, managers.size, 'DOAS control setpoint manager should sit on the inboard component outlet')
  end

  def test_forward_translates_cleanly
    @doas.build(doas_spec, @ctx)
    ft = OpenStudio::EnergyPlus::ForwardTranslator.new
    ft.translateModel(@model)
    assert_equal(0, ft.errors.size, ft.errors.map(&:logMessage).join("\n"))
  end

  def test_served_loop_without_oa_system_raises
    @air.build({ name: 'No OA AHU',
                 supply_components: [{ obj_type: 'FanConstantVolume', name: 'X Fan' }],
                 controls: [{ spm_type: 'Scheduled', spm_temp_f: 55.0 }] }, @ctx)
    spec = doas_spec
    spec[:air_loops] = ['No OA AHU']
    assert_raises(ArgumentError) { @doas.build(spec, @ctx) }
  end

  def test_relief_component_on_relief_stream
    spec = doas_spec
    spec[:relief_components] = [{ obj_type: 'FanConstantVolume', name: 'DOAS Relief Fan' }]
    doas = @doas.build(spec, @ctx)
    relief_fans = doas.airLoopHVACOutdoorAirSystem.reliefComponents.select { |c| c.to_FanConstantVolume.is_initialized }
    assert_equal(1, relief_fans.size)
  end

  def test_via_apply_hvac
    context = OpenstudioStandards::HVAC.apply_hvac(@model, { doas_info: [doas_spec] })
    assert_equal(1, @model.getAirLoopHVACDedicatedOutdoorAirSystems.size)
    refute(context.messages.any? { |m| m[:message].include?('dedicated outdoor air') && m[:message].include?('not yet') })
  end
end
