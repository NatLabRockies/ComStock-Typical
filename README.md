# ComStock-Typical

ComStock-Typical is a Ruby gem that extends the [OpenStudio SDK](https://www.openstudio.net/) with
methods for creating **typical** commercial building energy models. It is a fork of
[openstudio-standards](https://github.com/NREL/openstudio-standards), trimmed to the typical-building
path that [ComStock](https://github.com/NREL/ComStock) uses.

It has two main use-cases:

1. **Create a typical building model** — geometry, space types, loads, schedules, ventilation,
   service water heating, refrigeration, exterior lighting and HVAC — from user geometry, from
   programmatically generated geometry, or from a custom building specification.
2. **Apply code-minimum performance** to a model from the standards data: envelope constructions,
   HVAC efficiencies, fan and pump power, lighting power, and so on.

A typical building is not a code-compliance artifact. It follows minimally code-compliant equipment
efficiencies for its vintage because that is what buildings of that vintage tend to have, but its
purpose is to represent the existing stock, not to determine code.

## What this fork does not do

These belong to openstudio-standards and were removed here. If you need one, use openstudio-standards.

| Removed | Where it lives |
|---|---|
| DOE/PNNL prototype building creation | openstudio-standards |
| Appendix G / PRM baseline generation | openstudio-standards |
| NECB and BTAP (Canada), CBES, OEESC, IECC | openstudio-standards |
| Construction and material costing (RS-Means) | openstudio-standards |
| OpenStudio Application library export | openstudio-standards |

The standards that remain are the ASHRAE 90.1 family and DEER. DEER is kept only until the
California Title 24 data replaces it.

## Installing

This gem is not published to RubyGems and is not bundled with the OpenStudio installer. Add it to a
`Gemfile` from git:

```ruby
gem 'comstock-typical', git: 'https://github.com/NatLabRockies/ComStock-Typical.git', ref: 'main'
```

The gem is named `comstock-typical`, but the library keeps the `OpenstudioStandards` namespace and
the `lib/openstudio-standards/` layout so that fixes patch cleanly to and from openstudio-standards.
Both requires work, and both load the same code:

```ruby
require 'comstock-typical'
require 'openstudio-standards'
```

Because the second one still works, code written against openstudio-standards needs no edits to its
`require` lines. Do not install both gems into the same bundle: they provide the same file and
whichever loads first wins.

## Documentation

- [User Quick Start Guide](docs/UserQuickStartGuide.md) — creating a model
- [Custom Buildings](docs/CustomBuildings.md) — the building specification format
- [Features](docs/Features.md) — what the library does and how the pieces fit
- [Repository Structure](docs/RepositoryStructure.md) — what is in each directory
- [Code Architecture](docs/CodeArchitecture.md) — modules, the Standard class, and template lookup
- [Developer Information](docs/DeveloperInformation.md) — setup, tests, and the development process

There is no hosted API documentation. Generate it locally with `bundle exec rake doc:show`.
