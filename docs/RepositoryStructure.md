# Repository Structure

## ```/data```
Raw data shipped with the gem. It holds one thing: weather. Files here contain no code, and
everything under `/data` is packaged into the gem, so test fixtures do not belong here — they live
under `/test`. The standards JSONs are not here either; they live beside the Standard classes that
read them, under `/lib/openstudio-standards/standards/`.

### ```/weather```
Weather data for 50 representative locations: an `.epw` of typical annual weather, a `.ddy` of
design day information, and a `.stat` summary for each. The set is exactly what the climate zone map
and the tests reference; it is not a general-purpose weather library.

Rather than editing the 90.1 standards JSON files directly, make a pull request to the
[building energy standards database](https://github.com/pnnl/building-energy-standards-data).

## ```/docs```
The documentation you are reading. API documentation is not here — it is generated from the source
comments by `rake doc` and is not committed.

## ```/lib```
`comstock-typical.rb` is the gem entry point and `openstudio-standards.rb` is the loader. The gem is
named `comstock-typical`, but the library keeps the `OpenstudioStandards` namespace and the
`openstudio-standards/` directory layout so that fixes patch cleanly to and from
openstudio-standards. Both requires work and load the same code.

### ```/lib/openstudio-standards```
The functional code. Most subdirectories are modules under the `OpenstudioStandards` namespace, and
most of them hold a `data/` folder of the vintage-agnostic typical data that module consumes.

| Directory | What it provides |
|---|---|
| `constructions` | Create, modify and query constructions, materials and construction sets |
| `create_typical` | Build a whole typical model, from a building type or from a specification |
| `daylighting` | Add daylighting controls to a space |
| `equipment` | Typical plug loads and electrical transformers |
| `exterior_lighting` | Typical exterior lighting |
| `geometry` | Create, modify and query model geometry, including `create_bar` |
| `hvac` | Create, modify and query HVAC systems, including the CBECS system mapping |
| `infiltration` | Infiltration, including the NIST infiltration method |
| `interior_lighting` | Typical interior lighting |
| `occupancy` | Typical occupancy |
| `prototypes` | Assumptions that no standard governs but for which reasonable values exist: HVAC configuration, fan pressure drops, and similar |
| `qaqc` | Check a simulated model's results against expectations |
| `refrigeration` | Typical refrigerated cases and walk-ins |
| `refs` | The list of codes, standards and reports cited in the method documentation |
| `schedules` | Create, modify and query schedules, including parametric schedules |
| `service_water_heating` | Typical service water heating |
| `space` | Query model spaces |
| `space_type` | Space type data and the typical space type definitions |
| `sql_file` | Read results from the EnergyPlus `.sql` file |
| `standards` | The Standard classes and the vintage-specific standards data |
| `thermal_zone` | Query and modify thermal zones |
| `utilities` | Common tasks: running simulations, logging, object info |
| `ventilation` | Typical outdoor air ventilation |
| `weather` | Set and query model weather files and climate zones |

### ```/lib/openstudio-standards/standards```
The Standard classes, which modify model inputs to meet a specific code vintage — setting a chiller's
COP and performance curves from the template, capacity and compressor type, for example. Each family
has a subdirectory holding both its classes and its `data/` of standards JSONs. Methods defined
higher in the tree are re-implemented, and therefore overridden, further down. See the
{file:docs/CodeArchitecture.md Code Architecture page}.

Two families are present: `ashrae_90_1` and `deer`. DEER is kept only until the California Title 24
data replaces it.

## ```/test```
Unit tests. New functionality should arrive with tests.

| Directory | What is in it |
|---|---|
| `modules` | Tests for the `OpenstudioStandards` modules, one directory per module |
| `90_1_general` | Tests for Standard-class lookups against the 90.1 data |
| `os_stds_methods` | Tests for Standard-class methods, including the HVAC system tests |
| `helpers` | `minitest_helper.rb` and the shared test helpers |
| `models` | `.osm` fixtures, including `models/geometry` |

`test/BASELINE.md` records how to run the suite, what it costs, and which failures are inherited
from upstream. Tests write their run output into a gitignored `output/` directory beside the test
file, so the working directory does not matter.
