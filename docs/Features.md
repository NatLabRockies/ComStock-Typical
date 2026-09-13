# Features

ComStock-Typical has two main use-cases:

1. **Create a typical building model.** Build geometry, assign space types, and populate occupancy,
   lighting, plug loads, schedules, ventilation, infiltration, service water heating, refrigeration,
   exterior lighting and HVAC.
2. **Apply code-minimum performance.** Set envelope constructions, HVAC efficiencies, fan and pump
   power, and lighting power from the standards data for a given template and climate zone.

Model QAQC supports both: the {OpenstudioStandards::QAQC QAQC module} reads an EnergyPlus `.sql`
file back and checks a simulated model's envelope conductances, internal loads, schedules,
HVAC capacities and part-load ratios against expectations.

The DOE/PNNL prototype buildings and Appendix G baseline generation are not part of this fork. They
are code-determination tools and stay in openstudio-standards. A typical building may share geometry
and some component assumptions with a prototype, but it aims to represent buildings that exist
rather than buildings that a code describes.

## Two kinds of data

The split between the two use-cases is a split between two kinds of data, and it is the reason the
library is organized the way it is.

**Typical data is vintage-agnostic.** How many people are in a classroom, how many hours a
restaurant is open, how much outdoor air a patient room needs, what a walk-in freezer looks like:
these come from ASHRAE 62.1 and 170, CBECS, and field studies, and they do not change because a
building was built in 1985 rather than 2013. This data lives beside the module that consumes it, in
`lib/openstudio-standards/<module>/data/`.

**Standards data is vintage-specific.** The minimum efficiency of a 7.5-ton packaged unit, the
maximum lighting power density for an office, the required roof R-value in climate zone 5: these are
exactly what changes with the code vintage. This data lives under
`lib/openstudio-standards/standards/<family>/data/`, keyed by template.

A typical model of a 1985 building therefore gets 1985 equipment efficiencies and present-day
occupancy assumptions, which is the intent: the loads describe how the building is used, and the
template describes what it was legal to install when it was built.

## One method, many callers

The use-cases share subtasks, so the code is structured so that higher-level methods call the same
lower-level ones rather than carrying their own copies. The two entry points for building a model
converge almost immediately:

	OpenstudioStandards::CreateTypical.create_custom_building_from_spec(model, spec)
		OpenstudioStandards::CreateTypical.validate_custom_building_spec
		OpenstudioStandards::Geometry.create_bar_from_space_type_ratios
		OpenstudioStandards::CreateTypical.create_typical_building_from_model

	OpenstudioStandards::CreateTypical.create_typical_building_from_model(model, template)
		OpenstudioStandards::Occupancy.create_typical_occupancy
		OpenstudioStandards::InteriorLighting.create_typical_interior_lighting
		OpenstudioStandards::Equipment.create_typical_equipment
		OpenstudioStandards::Ventilation.create_typical_ventilation
		OpenstudioStandards::ServiceWaterHeating.create_typical_service_water_heating
		OpenstudioStandards::Refrigeration.create_typical_refrigeration
		OpenstudioStandards::HVAC.add_cbecs_hvac_system
		Standard#model_apply_prototype_hvac_assumptions
		Standard#model_apply_hvac_efficiency_standard

Where a method needs to behave **slightly differently** in two situations, it takes an argument
saying which. Where it needs to behave **very differently**, it is split into separate methods.

## Building from a specification

A building specification — a hash or JSON file naming a mix of space types with area ratios,
building form, schedule overrides and load overrides — is the most direct way to build a model of a
building that is not one of the standard building types. The format, its schema, and worked examples
are in the {file:docs/CustomBuildings.md Custom Buildings page}.
