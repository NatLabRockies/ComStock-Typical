require_relative '../../../helpers/minitest_helper'

class TestHVACCreatorAirLoopBuilder < Minitest::Test
  def setup
    @model = OpenStudio::Model::Model.new
    @ctx = OpenstudioStandards::HVAC::BuildContext.new(@model)
    @builder = OpenstudioStandards::HVAC::AirLoopBuilder
    @factory = OpenstudioStandards::HVAC::ComponentFactory
  end

  def unitary_spec
    { obj_type: 'AirLoopHVACUnitarySystem', name: 'PSZ Unitary',
      control_type: 'Load', fan_operation: { placement: 'BlowThrough' },
      components: [
        { obj_type: 'FanOnOff', name: 'PSZ Fan' },
        { obj_type: 'CoilCoolingDXSingleSpeed', name: 'PSZ DX', rated_cop: 3.5 },
        { obj_type: 'CoilHeatingGas', name: 'PSZ Gas', eff_percent: 80.0 }
      ] }
  end

  def psz_spec
    {
      name: 'PSZ-AC',
      design_info: { des_cool_sat_f: 55.0 },
      oa_control: { economizer: { type: 'FixedDryBulb', max_db_f: 75.0 }, ventilation: { min_oa_flow_cfm: 200.0 } },
      supply_components: [unitary_spec],
      controls: [{ spm_type: 'Scheduled', spm_temp_f: 55.0 }],
      availability: { night_cycle: { control_type: 'CycleOnAny' } }
    }
  end

  # ---- unitary composite (component layer) ----

  def test_unitary_assigns_subcomponents_by_role
    unitary = @factory.build(unitary_spec, @ctx).to_AirLoopHVACUnitarySystem.get
    assert(unitary.supplyFan.is_initialized)
    assert(unitary.coolingCoil.is_initialized)
    assert(unitary.heatingCoil.is_initialized)
    assert(unitary.supplyFan.get.to_FanOnOff.is_initialized)
    assert(unitary.coolingCoil.get.to_CoilCoolingDXSingleSpeed.is_initialized)
    assert_equal('Load', unitary.controlType)
    assert_equal('BlowThrough', unitary.fanPlacement.get)
  end

  def test_unitary_role_supplemental
    spec = { obj_type: 'AirLoopHVACUnitarySystem',
             components: [
               { obj_type: 'CoilHeatingGas', eff_percent: 80.0 },
               { obj_type: 'CoilHeatingElectric', role: 'supplemental' }
             ] }
    unitary = @factory.build(spec, @ctx).to_AirLoopHVACUnitarySystem.get
    assert(unitary.heatingCoil.get.to_CoilHeatingGas.is_initialized)
    assert(unitary.supplementalHeatingCoil.get.to_CoilHeatingElectric.is_initialized)
  end

  # ---- air loop (system layer) ----

  def test_builds_named_air_loop
    air_loop = @builder.build(psz_spec, @ctx)
    assert(air_loop.to_AirLoopHVAC.is_initialized)
    assert_equal('PSZ-AC', air_loop.name.get)
  end

  def test_sizing_system_cooling_sat
    air_loop = @builder.build(psz_spec, @ctx)
    assert_in_delta(12.78, air_loop.sizingSystem.centralCoolingDesignSupplyAirTemperature, 0.05)
  end

  def test_unitary_on_supply_side
    air_loop = @builder.build(psz_spec, @ctx)
    unitaries = air_loop.supplyComponents.select { |c| c.to_AirLoopHVACUnitarySystem.is_initialized }
    assert_equal(1, unitaries.size)
  end

  def test_oa_system_with_economizer
    air_loop = @builder.build(psz_spec, @ctx)
    assert(air_loop.airLoopHVACOutdoorAirSystem.is_initialized)
    controller = air_loop.airLoopHVACOutdoorAirSystem.get.getControllerOutdoorAir
    assert_equal('FixedDryBulb', controller.getEconomizerControlType)
    assert_in_delta(200.0, OpenStudio.convert(controller.minimumOutdoorAirFlowRate.get, 'm^3/s', 'cfm').get, 0.5)
  end

  def test_setpoint_manager_on_supply_outlet
    air_loop = @builder.build(psz_spec, @ctx)
    managers = air_loop.supplyOutletNode.setpointManagers.select { |m| m.to_SetpointManagerScheduled.is_initialized }
    assert_equal(1, managers.size)
  end

  def test_night_cycle_control
    air_loop = @builder.build(psz_spec, @ctx)
    assert_equal('CycleOnAny', air_loop.nightCycleControlType)
  end

  def test_registered_in_context
    air_loop = @builder.build(psz_spec, @ctx)
    assert_equal(air_loop, @ctx.air_loop('PSZ-AC'))
  end

  def test_mixed_air_spm_defaults_to_mixed_air_node
    spec = psz_spec
    spec[:controls] = [{ spm_type: 'MixedAir' }]
    air_loop = @builder.build(spec, @ctx)
    mixed_air_node = air_loop.airLoopHVACOutdoorAirSystem.get.mixedAirModelObject.get.to_Node.get
    managers = mixed_air_node.setpointManagers.select { |m| m.to_SetpointManagerMixedAir.is_initialized }
    assert_equal(1, managers.size, 'MixedAir setpoint manager should default to the mixed-air node')
    assert_equal(0, air_loop.supplyOutletNode.setpointManagers.count { |m| m.to_SetpointManagerMixedAir.is_initialized })
  end

  def test_spm_node_override_targets_named_supply_component
    spec = {
      name: 'VAV',
      supply_components: [
        { obj_type: 'CoilHeatingGas', name: 'Preheat', eff_percent: 80.0 },
        { obj_type: 'FanConstantVolume', name: 'SF' }
      ],
      controls: [{ spm_type: 'Scheduled', spm_temp_f: 55.0, spm_node: 'Preheat' }]
    }
    air_loop = @builder.build(spec, @ctx)
    preheat = air_loop.supplyComponents.find { |c| c.name.is_initialized && c.name.get == 'Preheat' }
    preheat_outlet = preheat.to_StraightComponent.get.outletModelObject.get.to_Node.get
    assert_equal(1, preheat_outlet.setpointManagers.count { |m| m.to_SetpointManagerScheduled.is_initialized })
    assert_equal(0, air_loop.supplyOutletNode.setpointManagers.count { |m| m.to_SetpointManagerScheduled.is_initialized })
  end

  def test_supply_components_airflow_order
    # discrete components listed inlet-most first: heating, then cooling, then fan
    spec = {
      name: 'VAV',
      supply_components: [
        { obj_type: 'CoilHeatingGas', name: 'HC', eff_percent: 80.0 },
        { obj_type: 'CoilCoolingDXSingleSpeed', name: 'CC' },
        { obj_type: 'FanConstantVolume', name: 'SF' }
      ],
      controls: [{ spm_type: 'Scheduled', spm_temp_f: 55.0 }]
    }
    air_loop = @builder.build(spec, @ctx)
    names = air_loop.supplyComponents.map { |c| c.name.is_initialized ? c.name.get : nil }.compact
    assert(names.index('HC') < names.index('CC'), 'heating coil should be upstream of cooling coil')
    assert(names.index('CC') < names.index('SF'), 'cooling coil should be upstream of the fan')
  end

  # ---- relief / return streams ----

  def test_relief_component_on_relief_node
    spec = psz_spec
    spec[:relief_components] = [{ obj_type: 'FanConstantVolume', name: 'Relief Fan' }]
    air_loop = @builder.build(spec, @ctx)
    relief_node = air_loop.reliefAirNode.get
    relief_fans = @model.getFanConstantVolumes.select { |f| f.name.get == 'Relief Fan' }
    assert_equal(1, relief_fans.size)
    assert(relief_fans.first.outletModelObject.get.to_Node.get == relief_node ||
           relief_fans.first.inletModelObject.get.to_Node.get == relief_node,
           'relief fan should sit on the relief air node')
  end

  def test_return_component_on_return_node
    spec = psz_spec
    spec[:return_components] = [{ obj_type: 'FanConstantVolume', name: 'Return Fan' }]
    air_loop = @builder.build(spec, @ctx)
    return_fans = @model.getFanConstantVolumes.select { |f| f.name.get == 'Return Fan' }
    assert_equal(1, return_fans.size)
    return_node = air_loop.returnAirNode.get
    assert(return_fans.first.outletModelObject.get.to_Node.get == return_node ||
           return_fans.first.inletModelObject.get.to_Node.get == return_node,
           'return fan should sit on the return air node')
  end

  def test_relief_without_oa_system_warns
    spec = {
      name: 'No OA',
      supply_components: [{ obj_type: 'FanConstantVolume', name: 'SF' }],
      relief_components: [{ obj_type: 'FanConstantVolume', name: 'Relief Fan' }],
      controls: [{ spm_type: 'Scheduled', spm_temp_f: 55.0 }]
    }
    @builder.build(spec, @ctx)
    assert_equal(0, @model.getFanConstantVolumes.count { |f| f.name.get == 'Relief Fan' })
    assert(@ctx.messages.any? { |m| m[:message].include?('relief_components') })
  end

  # ---- dual duct ----

  def test_dual_duct_places_components_on_branches
    spec = {
      name: 'DualDuct',
      ahu_type: 'DualDuct',
      supply_components: [
        { obj_type: 'FanConstantVolume', name: 'Supply Fan' },
        { obj_type: 'CoilHeatingElectric', name: 'Hot Deck', branch: 0 },
        { obj_type: 'CoilCoolingDXSingleSpeed', name: 'Cold Deck', branch: 1 }
      ],
      controls: [{ spm_type: 'Scheduled', spm_temp_f: 55.0 }]
    }
    air_loop = @builder.build(spec, @ctx)
    assert_equal(2, air_loop.supplyOutletNodes.size, 'dual duct loop has two supply outlet nodes')
    assert(@model.getCoilHeatingElectrics.any? { |c| c.name.get == 'Hot Deck' })
    assert(@model.getCoilCoolingDXSingleSpeeds.any? { |c| c.name.get == 'Cold Deck' })
  end

  # ---- retrofit (existing: true) ----

  def test_existing_applies_to_loop_without_new_loop
    @builder.build(psz_spec, @ctx)
    before = @model.getAirLoopHVACs.size
    @builder.build({ name: 'PSZ-AC', existing: true,
                     design_info: { des_cool_sat_f: 50.0 },
                     controls: [{ spm_type: 'Scheduled', spm_temp_f: 60.0 }] }, @ctx)
    assert_equal(before, @model.getAirLoopHVACs.size, 'retrofit must not create a new air loop')
    existing = @ctx.air_loop('PSZ-AC')
    assert_in_delta(10.0, existing.sizingSystem.centralCoolingDesignSupplyAirTemperature, 0.05,
                    'retrofit reapplies sizing to the existing loop')
    assert_equal(1, existing.supplyOutletNode.setpointManagers.count { |m| m.to_SetpointManagerScheduled.is_initialized })
  end

  def test_existing_dual_duct_raises
    assert_raises(ArgumentError) do
      @builder.build({ name: 'X', existing: true, ahu_type: 'DualDuct' }, @ctx)
    end
  end

  def test_existing_null_airflow_autosizes
    spec = psz_spec
    spec[:design_info][:des_supply_airflow_cfm] = 2000.0
    @builder.build(spec, @ctx)
    loop = @ctx.air_loop('PSZ-AC')
    refute(loop.isDesignSupplyAirFlowRateAutosized, 'flow should be hard-set before retrofit')
    @builder.build({ name: 'PSZ-AC', existing: true, design_info: { des_supply_airflow_cfm: nil } }, @ctx)
    assert(loop.isDesignSupplyAirFlowRateAutosized, 'a null design airflow clears (autosizes) the field')
  end
end
