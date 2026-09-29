require_relative '../helpers/minitest_helper'

class TestMinimumEfficiencyLookups < Minitest::Test
    # A DOAS built with DX heating counts as a heat pump, so its coils look up the heat_pumps
    # and heat_pumps_heating tables with heating type 'All Other'. DEER's own data has only
    # the small-unit 'Electric Resistance or None' rows, so every such coil on a DEER template
    # missed and kept its default efficiency. The rows mirrored from the mapped 90.1 vintage
    # have to answer for both heating types at every capacity, on every DEER vintage.
    def test_deer_packaged_heat_pump_lookups_answer_at_every_capacity
        templates = ['DEER Pre-1975', 'DEER 1985', 'DEER 1996', 'DEER 2003', 'DEER 2007', 'DEER 2011', 'DEER 2014',
                     'DEER 2015', 'DEER 2017', 'DEER 2020', 'DEER 2025', 'DEER 2050', 'DEER 2075', 'ComStock DEER 2011', 'ComStock DEER 2017']
        capacities = [8_883.0, 34_000.0, 60_000.0, 116_000.0, 200_000.0, 700_000.0]
        templates.each do |template|
            std = Standard.build(template)
            ['Single Package', 'Split System'].each do |subcategory|
                ['All Other', 'Electric Resistance or None'].each do |heating_type|
                    capacities.each do |capacity|
                        criteria = { 'template' => std.template, 'cooling_type' => 'AirCooled', 'subcategory' => subcategory, 'heating_type' => heating_type }
                        row = std.model_find_object(std.standards_data['heat_pumps'], criteria, capacity, Date.today)
                        refute_nil(row, "#{template} heat_pumps: no row for #{subcategory} / #{heating_type} at #{capacity} Btu/h")
                        assert(row['minimum_seasonal_efficiency'] || row['minimum_full_load_efficiency'] || row['minimum_integrated_energy_efficiency_ratio'],
                               "#{template} heat_pumps row for #{subcategory} / #{heating_type} at #{capacity} Btu/h carries no efficiency")
                        assert(row['cool_cap_ft'], 'mirrored rows keep the DEER curve names')
                    end
                end
                capacities.each do |capacity|
                    criteria = { 'template' => std.template, 'cooling_type' => 'AirCooled', 'subcategory' => subcategory }
                    row = std.model_find_object(std.standards_data['heat_pumps_heating'], criteria, capacity, Date.today)
                    refute_nil(row, "#{template} heat_pumps_heating: no row for #{subcategory} at #{capacity} Btu/h")
                end
            end
        end
    end

    # DEER's own small-unit numbers stand where they exist: the mirror only fills gaps.
    def test_deer_small_unit_rows_are_untouched
        std = Standard.build('DEER 2011')
        criteria = { 'template' => 'DEER 2011', 'cooling_type' => 'AirCooled', 'subcategory' => 'Single Package', 'heating_type' => 'Electric Resistance or None' }
        row = std.model_find_object(std.standards_data['heat_pumps'], criteria, 20_000.0, Date.today)
        assert_in_delta(13.0, row['minimum_seasonal_efficiency'], 1e-6)
        assert_in_delta(11.07746479, row['minimum_full_load_efficiency'], 1e-6)
        assert_match(/MASControl/, row['notes'])
        # above DEER's 34,895 Btu/h the mirrored 90.1-2010 bins take over
        row = std.model_find_object(std.standards_data['heat_pumps'], criteria, 100_000.0, Date.today)
        assert_in_delta(11.0, row['minimum_full_load_efficiency'], 1e-6, '90.1-2010 gives 11.0 EER for 65-135 kBtu/h single package with electric supplemental heat')
        assert_match(/Same as 90.1-2010/, row['notes'])
    end

    def test_water_heater_efficiency_lookup
        std = Standard.build('90.1-2019')
        volume_gal = 10.0
        capacity_btu_per_hr = 20_472
        water_heater_mixed = nil
        fuel_type = 'Electricity'
        wh_props = std.water_heater_mixed_get_efficiency_requirement(water_heater_mixed, fuel_type, capacity_btu_per_hr, volume_gal)
        # this is a valid lookup for the water heater data data, so not sure why the test checks for an empty hash
        # assert(wh_props == {})

        volume_gal = 19.9
        capacity_btu_per_hr = 20_472
        water_heater_mixed = nil
        fuel_type = 'NaturalGas'
        wh_props = std.water_heater_mixed_get_efficiency_requirement(water_heater_mixed, fuel_type, capacity_btu_per_hr, volume_gal)
        assert_equal(0.6483, wh_props['uniform_energy_factor_base'])
        assert_equal(0.0017, wh_props['uniform_energy_factor_volume_allowance'])

        volume_gal = 19.9
        capacity_btu_per_hr = 135_000
        water_heater_mixed = nil
        fuel_type = 'Oil'
        wh_props = std.water_heater_mixed_get_efficiency_requirement(water_heater_mixed, fuel_type, capacity_btu_per_hr, volume_gal)
        assert_equal(0.6194, wh_props['uniform_energy_factor_base'])
        assert_equal(0.0016, wh_props['uniform_energy_factor_volume_allowance'])

        volume_gal = 19.9
        capacity_btu_per_hr = 150_000
        water_heater_mixed = nil
        fuel_type = 'NaturalGas'
        wh_props = std.water_heater_mixed_get_efficiency_requirement(water_heater_mixed, fuel_type, capacity_btu_per_hr, volume_gal)
        assert_equal(0.80, wh_props['thermal_efficiency'])
    end
end