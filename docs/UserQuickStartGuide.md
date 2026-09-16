# User Quick Start Guide

## Installing

ComStock-Typical is not published to RubyGems and is not bundled with the OpenStudio installer. Add
it to a `Gemfile` from git:

```ruby
gem 'comstock-typical', git: 'https://github.com/NatLabRockies/ComStock-Typical.git', ref: 'main'
```

Then run it under the OpenStudio CLI, which supplies the OpenStudio SDK:

```
openstudio --bundle Gemfile --bundle_path ./.bundle/install execute_ruby_script my_script.rb
```

The gem is named `comstock-typical`, but it keeps the `OpenstudioStandards` namespace, so
`require 'openstudio-standards'` still works and existing code needs no edits. Do not install this
gem and openstudio-standards into the same bundle — both provide `lib/openstudio-standards.rb`, and
whichever loads first wins.

## Create a typical building from existing geometry

Given a model that already has geometry with space types assigned,
`create_typical_building_from_model` populates everything else: loads, schedules, ventilation,
infiltration, service water heating, refrigeration, exterior lighting, HVAC, and the code-minimum
performance for the template.

```ruby
require 'openstudio'
require 'openstudio-standards'

model = OpenStudio::Model::Model.load('my_building.osm').get

OpenstudioStandards::CreateTypical.create_typical_building_from_model(
  model,
  'ComStock 90.1-2013',
  climate_zone: 'ASHRAE 169-2013-4A'
)

model.save('my_typical_building.osm', true)
```

The template is a registered Standard name, matched exactly. Sixty are registered; see the
{file:docs/CodeArchitecture.md Code Architecture page} for what they are and how the lookup works.

Every other argument is a keyword with a default, so the call above is the short form. The API
documentation for the method lists all of them — HVAC system type and fuels, lighting generation,
whether to add daylighting controls, elevators, internal mass, exhaust, and so on.

## Create a custom building type

To build a model of your own mix of space types — custom area ratios, building form, schedule
overrides and load overrides — pass a specification hash or JSON file to
`create_custom_building_from_spec`. It generates the geometry from the space type ratios and then
runs the same typical-building path as above.

```ruby
spec = JSON.parse(File.read('my_building_spec.json'), symbolize_names: true)
model = OpenStudio::Model::Model.new
OpenstudioStandards::CreateTypical.create_custom_building_from_spec(model, spec)
```

The specification format, its JSON schema, and worked examples are on the
{file:docs/CustomBuildings.md Custom Buildings page}. Ready-made examples ship in
`lib/openstudio-standards/create_typical/data/examples/`.

## Using the library in a measure

Add the gem to the workflow's bundle, then require it in `measure.rb`:

```ruby
class MyMeasureName < OpenStudio::Measure::ModelMeasure
  require 'openstudio-standards'
  ...
```

Measures written against openstudio-standards work unchanged as long as they only use the parts this
fork keeps. Prototype building creation, Appendix G baseline generation and the NECB, CBES, OEESC and
IECC standards are not here — a measure that calls into those needs openstudio-standards instead.
