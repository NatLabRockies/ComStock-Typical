require_relative '../../helpers/minitest_helper'

class TestEquipmentCreate < Minitest::Test
  def setup
    @equip = OpenstudioStandards::Equipment
  end

  def test_create_typical_equipment
    # load model and set up weather file
    template = '90.1-2013'
    climate_zone = 'ASHRAE 169-2013-4A'
    std = Standard.build(template)
    model = std.safe_load_model("#{__dir__}/../../models/geometry/ASHRAEPrimarySchool.osm")
    OpenstudioStandards::Weather.model_set_building_location(model, climate_zone: climate_zone)

    # set equipment space types
    std.prototype_space_type_map(model, set_additional_properties: true)
    assert_equal(0, model.getElectricEquipmentDefinitions.size)
    result = @equip.create_typical_equipment(model)
    assert(result)
    assert_equal(11, model.getElectricEquipmentDefinitions.size)
    space_type = model.getSpaceTypeByName('PrimarySchool Kitchen').get
    elec_equip_def = space_type.electricEquipment[0].to_ElectricEquipment.get.electricEquipmentDefinition
    assert_in_delta(OpenStudio.convert(2.2516, 'W/ft^2', 'W/m^2').get, elec_equip_def.wattsperSpaceFloorArea.get, 0.01)
    gas_equip_def = space_type.gasEquipment[0].to_GasEquipment.get.gasEquipmentDefinition
    assert_in_delta(OpenStudio.convert(453.7, 'Btu/hr*ft^2', 'W/m^2').get, gas_equip_def.wattsperSpaceFloorArea.get, 0.01)
  end

  # a space type built from a typical (all-level) space type name: no standards building type
  def typical_space_type(model, name, electric:, gas:)
    space_type = OpenStudio::Model::SpaceType.new(model)
    space_type.setName(name)
    space_type.setStandardsSpaceType(name)
    space_type.additionalProperties.setFeature('electric_equipment_space_type', electric)
    space_type.additionalProperties.setFeature('natural_gas_equipment_space_type', gas) unless gas.nil?
    return space_type
  end

  def gas_btu_per_hr_ft2(instance)
    OpenStudio.convert(instance.gasEquipmentDefinition.wattsperSpaceFloorArea.get, 'W/m^2', 'Btu/hr*ft^2').get
  end

  def test_equipment_space_type_names_round_trip
    assert_equal(['kitchen'], @equip.equipment_space_type_names('kitchen'))
    assert_equal([], @equip.equipment_space_type_names('na'))
    assert_equal([], @equip.equipment_space_type_names(''))
    assert_equal([], @equip.equipment_space_type_names(nil))
    assert_equal('kitchen', @equip.equipment_space_type_feature_value('kitchen'))
    assert_equal('kitchen', @equip.equipment_space_type_feature_value(['kitchen']))
    several = @equip.equipment_space_type_feature_value(['kitchen - primary school', 'bakery'])
    assert_equal(['kitchen - primary school', 'bakery'], @equip.equipment_space_type_names(several))
  end

  # rows keyed on a building type match only that building type; rows with none match any
  def test_select_equipment_space_type_properties
    rows = @equip.gas_equipment_space_type_data
    row = @equip.select_equipment_space_type_properties(rows, :natural_gas_equipment_space_type_name, :gas_equipment_per_area, 'kitchen', 'Hospital')
    assert_equal(51.16, row[:gas_equipment_per_area])
    row = @equip.select_equipment_space_type_properties(rows, :natural_gas_equipment_space_type_name, :gas_equipment_per_area, 'kitchen - primary school', nil)
    assert_equal(453.7, row[:gas_equipment_per_area])
    row = @equip.select_equipment_space_type_properties(rows, :natural_gas_equipment_space_type_name, :gas_equipment_per_area, 'kitchen - primary school', 'Hospital')
    assert_equal(453.7, row[:gas_equipment_per_area], 'a row with no building type matches any building type')
    row = @equip.select_equipment_space_type_properties(rows, :natural_gas_equipment_space_type_name, :gas_equipment_per_area, 'kitchen', nil)
    assert_nil(row, 'no fallback: a typical kitchen has no row of its own')
    row = @equip.select_equipment_space_type_properties(rows, :natural_gas_equipment_space_type_name, :gas_equipment_per_area, 'kitchen', nil, building_type_fallback: true)
    assert_equal(203.98, row[:gas_equipment_per_area], 'fallback: the median kitchen across building types')
  end

  def test_typical_space_types_take_their_own_objects
    model = OpenStudio::Model::Model.new
    school_kitchen = typical_space_type(model, 'food preparation - primary school', electric: 'kitchen_electric_equipment', gas: 'kitchen - primary school')
    bakery = typical_space_type(model, 'food preparation - bakery', electric: 'kitchen_electric_equipment', gas: 'bakery')
    # the grocery service area keys both loads to its own objects, so neither falls to the median
    deli_bakery = typical_space_type(model, 'food preparation - deli/bakery', electric: 'deli/bakery', gas: 'deli/bakery')
    kitchen = typical_space_type(model, 'food preparation', electric: 'kitchen_electric_equipment', gas: 'kitchen')
    # a typical space type has no standards building type, so an office building's data centers took the
    # cross-building median (100 and 40 W/ft2, the small data center rows) and its offices the median 0.64;
    # the building-type-free rows carry the Office prototype's data centers and a CBECS-calibrated office
    office = typical_space_type(model, 'office', electric: 'office_open_electric_equipment', gas: nil)
    high_ite = typical_space_type(model, 'datacenter/high ite', electric: 'datacenter_high_ite_equipment', gas: nil)
    low_ite = typical_space_type(model, 'datacenter/low ite', electric: 'datacenter_low_ite_equipment', gas: nil)
    # warehouse storage carried the prototype's 0.06 and 0.11 W/ft2; CBECS puts a warehouse at about 0.45 W/ft2
    bulk = typical_space_type(model, 'storage - warehouse - medium to bulky palletized items', electric: 'warehouse_bulk_storage_electric_equipment', gas: nil)
    fine = typical_space_type(model, 'storage - warehouse - smaller hand-carried items', electric: 'warehouse_fine_storage_electric_equipment', gas: nil)

    assert(@equip.create_typical_equipment(model, building_type_fallback: true))
    assert_in_delta(453.7, gas_btu_per_hr_ft2(school_kitchen.gasEquipment[0]), 0.01)
    assert_in_delta(8.54, gas_btu_per_hr_ft2(bakery.gasEquipment[0]), 0.01)
    assert_in_delta(100.0, gas_btu_per_hr_ft2(deli_bakery.gasEquipment[0]), 0.01, 'grocery service area: about half a restaurant kitchen')
    deli_bakery_w_per_ft2 = deli_bakery.electricEquipment[0].electricEquipmentDefinition.wattsperSpaceFloorArea.get / 10.7639
    assert_in_delta(25.0, deli_bakery_w_per_ft2, 0.01, 'grocery service area electric equipment: a little above the kitchen median')
    w_per_ft2 = ->(st) { st.electricEquipment[0].electricEquipmentDefinition.wattsperSpaceFloorArea.get / 10.7639 }
    assert_in_delta(1.1, w_per_ft2.call(office), 0.001, 'office plug loads, CBECS-calibrated, not the 0.64 cross-building median')
    assert_in_delta(45.0, w_per_ft2.call(high_ite), 0.01, 'high ITE data center at the Office prototype value, not the 100 median')
    assert_in_delta(1.56, w_per_ft2.call(low_ite), 0.001, 'low ITE data center at the Office prototype value, not the 40 median')
    assert_in_delta(0.4, w_per_ft2.call(bulk), 0.001, 'bulk warehouse storage, CBECS-calibrated')
    assert_in_delta(0.4, w_per_ft2.call(fine), 0.001, 'fine warehouse storage, CBECS-calibrated')
    assert_in_delta(203.98, gas_btu_per_hr_ft2(kitchen.gasEquipment[0]), 0.01)
    assert_equal('food preparation Gas Equip', kitchen.gasEquipment[0].name.to_s)
  end

  def test_space_type_with_several_equipment_objects
    model = OpenStudio::Model::Model.new
    names = ['kitchen - primary school', 'bakery']
    kitchen = typical_space_type(model, 'food preparation', electric: 'kitchen_electric_equipment', gas: @equip.equipment_space_type_feature_value(names))

    assert(@equip.create_typical_equipment(model, building_type_fallback: true))
    assert_equal(2, kitchen.gasEquipment.size)
    by_name = kitchen.gasEquipment.map { |g| [g.name.to_s, gas_btu_per_hr_ft2(g)] }.to_h
    assert_in_delta(453.7, by_name['food preparation kitchen - primary school Gas Equip'], 0.01)
    assert_in_delta(8.54, by_name['food preparation bakery Gas Equip'], 0.01)

    # re-applying replaces rather than accumulates
    assert(@equip.space_type_apply_typical_gas_equipment(kitchen, 'bakery'))
    assert_equal(1, kitchen.gasEquipment.size)
    assert_equal('food preparation Gas Equip', kitchen.gasEquipment[0].name.to_s)
  end
end
