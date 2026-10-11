# The HVAC Creator

The HVAC creator builds complete HVAC systems from a single declarative input: a Hash (or JSON
document) describing the systems you want, rather than a sequence of calls that assemble them.

```ruby
OpenstudioStandards::HVAC.apply_hvac(model, spec)
```

The zones must already exist in the model. `apply_hvac` returns a build context exposing what it
created, indexed by name.

The input format is defined by
[`hvac_creator_schema.json`](../lib/openstudio-standards/hvac/hvac_creator_schema.json), a JSON
Schema (draft 2020-12). Working examples live in
[`creator/examples/`](../lib/openstudio-standards/hvac/creator/examples) and are exercised by the
test suite, so they cannot drift from the code. A larger worked example, a spec for a real
building written from its energy audit report together with the system description and the
audit review it was derived from, is under [`docs/examples/hvac_creator/`](examples/hvac_creator);
it is documentation, not a test fixture.

## Build order

Sections are built in a fixed order, and **a name may only reference something built before it**:

1. `schedules` — constant schedules any later section may name
2. `plant_loop_info` — primary loops in listed order, then their secondary loops
3. `vrf_info` — variable refrigerant flow condensing units
4. `air_system_info` — air loops
5. `doas_info` — dedicated outdoor air systems
6. `zone_info` — terminals, then zone equipment, then sizing, humidistat, and air paths
7. deferred cross-loop passes declared on plant loops: waterside economizers, two-pipe changeover,
   supply-water-temperature control
8. `ems_info` — EnergyManagementSystem objects

So a cooling coil on an air loop may name the chilled water loop that serves it, but a plant loop
may not name an air loop. Entries within a section are ordered too: a chiller may not name a
condenser loop listed after its own loop. `apply_hvac` validates this and raises naming the
offending path, rather than failing later inside a builder.

The deferred passes are the exception: they run after every loop and zone exists, so a hot water
loop may name the chilled water loop it pairs with even when that loop is listed after it.

## Units

Every physical quantity is expressed in both IP and SI, distinguished by the key suffix:

```json
{ "supply_temp_f": 180.0 }
{ "supply_temp_c": 82.22 }
```

Supply either. Supplying both is allowed when they agree; when they disagree the factory raises
rather than silently preferring one. The suffixes are `_f`/`_c` (temperature), `_r`/`_k`
(temperature difference), `_cfm`/`_m3s` (air flow), `_gpm`/`_m3s` (water flow), `_inh2o`/`_pa`
(pressure), `_fth2o`/`_pa` (pump head), `_btuh`/`_w` (capacity).

## Referring to things by name

Objects are wired together by name, not by nesting:

- `plant_loop_name`, `hot_water_loop_name`, `chilled_water_loop_name`, `condenser_loop_name` — the
  plant loop a coil or chiller connects to
- `air_loop_name` — the air loop a zone's terminal attaches to
- `cu_name` — the condensing unit a variable refrigerant flow terminal belongs to
- `zone_name`, `control_zone_name`, `return_plenum_name` — thermal zones
- `*_sch_name` — schedules

A name the spec does not declare is assumed to already exist in the model, which is how a spec can
extend a model that already has systems in it. That case warns rather than failing, so a typo is
visible without blocking a legitimate reference.

## Topology

A plant loop's supply side is described as branches:

```json
"supply_inlet_components": [ { "obj_type": "PumpVariableSpeed", "pump_head_fth2o": 60.0 } ],
"supply_branches": [
  [ { "obj_type": "BoilerHotWater", "name": "Boiler 1" } ],
  [ { "obj_type": "BoilerHotWater", "name": "Boiler 2" } ]
]
```

`supply_inlet_components` are placed in series from the loop inlet. Each entry in `supply_branches`
is one parallel branch, and the components within a branch are placed in series along it. Air loops
follow the same idea: `supply_components` are placed in airflow order, inlet-most first.

Loops carry the conventional adiabatic bypass and outlet pipes by default; `loop_pipes: false` opts
out.

## Components and setpoint managers

A component is an object with an `obj_type` naming an OpenStudio class; a setpoint manager has an
`spm_type`. Every value either enum accepts has a builder — the test suite asserts the schema and
the registries agree, in both directions.

A component may carry a `preset`, which selects a packaged set of performance curves or fan data
rather than spelling out coefficients. Performance curves can also be given directly:

```json
"fan_power_ratio_curve": {
  "type": "Cubic",
  "coefficients": [0.33162901, -0.88567609, 0.60556507, 0.9484823],
  "min_x": 0.0, "max_x": 1.0
}
```

By default a setpoint manager is placed on its loop's supply outlet node. `spm_node` places it
elsewhere, naming the component whose outlet it should sit on.

## The examples

| Example | What it shows |
| --- | --- |
| `psz_ac.json` | The simplest complete air system: one packaged unit per zone. Start here. |
| `vav_chw_hw.json` | Multi-zone VAV over chilled and hot water plants, two chillers, a condenser loop, and a waterside economizer as a deferred pass. |
| `doas_fpfc.json` | A zone served by an air loop *and* its own zone equipment at once. |
| `vrf_doas.json` | Condensing units built before the terminals that name them. |
| `wshp_ground_loop.json` | A ground heat exchanger driven by an EMS program, and a shared schedule two objects must follow. |

## Relationship to the system creators

The `model_add_*` methods in `create_hvac_system.rb` are thin translations of their keyword
arguments into a spec, which they hand to `apply_hvac`. Their public signatures and return values
are unchanged, so calling code is unaffected; the factory is simply the single object-creation path
underneath. `model_add_low_temp_radiant` is the deliberate exception — its climate-zone-dependent
constructions, surface reassignment, and EMS control strategies are not declarative, and only its
per-zone radiant loop goes through the factory.
