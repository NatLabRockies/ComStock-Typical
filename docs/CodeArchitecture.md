# Code Architecture

There are two halves to the library, and they are organized differently on purpose.

- **Modules** hold generic methods that create, modify or query an OpenStudio model, together with
  the vintage-agnostic typical data they consume. They are plain namespaced modules with module
  functions.
- **Standard classes** hold the vintage-specific behavior, together with the standards data keyed by
  template. They are a class hierarchy, because vintages mostly share behavior and differ in
  specific places.

## Modules

Each module lives in `lib/openstudio-standards/<name>/` under the `OpenstudioStandards` namespace,
and most carry a `data/` folder of the JSON data that module reads. See the
{file:docs/RepositoryStructure.md Repository Structure page} for the full list, and the API
documentation for the methods.

	constructions       geometry            schedules
	create_typical      hvac                service_water_heating
	daylighting         infiltration        space
	equipment           interior_lighting   space_type
	exterior_lighting   occupancy           sql_file
	prototypes          qaqc                thermal_zone
	refrigeration       utilities           ventilation
	weather

Module methods are called on the module, not on a model:

```ruby
OpenstudioStandards::Occupancy.create_typical_occupancy(model, template)
```

## Standard classes

Each code vintage — ASHRAE 90.1-2013, say — is one class. Vintages share a great deal of behavior,
so rather than copying it, code reuse is by inheritance:

- `Standard` (_abstract_)
  - `ASHRAE901` (_abstract_)
    - `ASHRAE9012004` (_concrete_)
      - `ComStockASHRAE9012004` (_concrete_)
    - `ASHRAE9012007`, `ASHRAE9012010`, `ASHRAE9012013`, `ASHRAE9012016`, `ASHRAE9012019`
    - `DOERef1980to2004`, `DOERefPre1980`, `NRELZNEReady2017`, `ZEAEDGMultifamily`
  - `DEER` (_abstract_)
    - `DEER1985`, `DEER1996`, … and their `ComStockDEER…` subclasses

A method implemented in `Standard` is used by every class below it. A subclass that has a special
requirement reimplements the method with its own logic, and that reimplementation is used only by
objects of that class — it does not propagate back up to `Standard` or sideways to a sibling.

The `ComStock…` classes are subclasses of the vintage they modify. They exist to reflect the U.S.
building stock more closely than the code vintage alone would, and they inherit everything they do
not override.

### Building one

A Standard is built by name, not by constructor. Every concrete class registers its name at load
time with `register_standard`, which records it in `Standard::STANDARDS_LIST`, and `Standard.build`
looks it up:

```ruby
standard = Standard.build('ComStock 90.1-2013')
standard.model_apply_hvac_efficiency_standard(model, 'ASHRAE 169-2013-4A')
```

The name is a string and is matched exactly; an unregistered name raises. Sixty names are registered
in this fork: 18 in the ASHRAE 90.1 family and 42 DEER.

### Where the numbers come from

A Standard's data is the set of JSON tables in its family's `data/` directory, merged so that a more
specific vintage overrides a more general one. `standards_data` exposes the merged result, and
lookups go through `model_find_object` and `model_find_objects`, which filter a table by search
criteria and, where a table is capacity-dependent, by capacity and date:

```ruby
search_criteria = standard.coil_dx_find_search_criteria(coil)
props = standard.model_find_object(standard.standards_data['heat_pumps_heating'],
                                   search_criteria, capacity_btu_per_hr, Date.today)
```

This is the seam between the two halves of the library. A module method decides *that* a coil needs
an efficiency; the Standard decides *what* that efficiency is for the template in hand.
