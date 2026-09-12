# Phase 3 test baseline

This records the state of the kept test suite at the end of the trim phases, when
NECB/BTAP, DEER, CBES, OEESC, IECC (Phase 1), the Appendix G PRM machinery (Phase 2) and
the DOE prototype buildings (Phase 3) had been removed. Every later phase compares against
it, and the Phase 4 parity gate uses it as its reference.

## How to reproduce it

The OpenStudio CLI takes about 52 seconds to start, so running the suite file by file spends
longer starting up than testing. Load every kept test file into one CLI process instead:

```bash
"C:/openstudio-3.10.0/bin/openstudio.exe" execute_ruby_script test/baseline_run.rb
```

`test/baseline_run.rb` pushes `lib` and `test/helpers` onto the load path and requires every
`test_*.rb` under `test/modules`, `test/90_1_general` and `test/os_stds_methods`. Run it from
the repository root: four tests in `test/modules/sql_file` write to a relative `output/AR`.
Set `CHECK_ROOT` to point it at another tree, which is how a failure here is checked against
upstream before being called a regression.

## The tests that run EnergyPlus

50 of the 664 tests take 90% of the 108 minutes, and nearly all of that is EnergyPlus. The
measured split, from the run below:

| Class | Time | Tests |
| --- | --- | --- |
| `TestAddHVACSystems` | 47 min | 15 |
| `TestEnergyUse` | 12 min | 6 |
| `TestScheduleComparison` | 6.5 min | 1 |
| `TestQAQC` | 5.7 min | 1 |
| `TestSqlFile` | 5.0 min | 4 |
| `TestUnmetHours` | 3.1 min | 7 |

Those simulations are not all the same kind of thing. `TestAddHVACSystems` runs a sizing run and
an annual run per case and then asserts on unmet occupied hours: the simulation *is* the test,
and it is the only thing in the suite that checks a built HVAC system can actually hold setpoint.
Shortening its run period would not help, because the thresholds it checks are annual and a
shorter period would miss the seasonal extremes that produce unmet hours at all.

The four `sql_file` classes are the opposite. Each runs one simulation in `setup` and then
asserts only on `OpenstudioStandards::SqlFile` reader methods. The simulation there is a fixture
generator, not the subject, and those 21 minutes buy coverage of code that parses a file. A
committed `.sql` fixture would remove the simulation entirely and make them deterministic; that
is worth doing and has not been done.

Set `SKIP_SIMULATION_TESTS` to skip every test that runs EnergyPlus:

```bash
SKIP_SIMULATION_TESTS=true openstudio execute_ruby_script test/baseline_run.rb
```

Simulations run by default, so CI and the numbers below are unaffected by the control existing.
Skipped tests report as skips rather than passes, so a partial run cannot be mistaken for a full
one. It currently covers 34 tests worth about 73 of the 108 minutes. Do not use it to get a green
run.

## Regenerating the CI test list

`test/ci_tests.txt` lists the files CI runs, relative to `test/`. Regenerate it from the kept tree
after adding, moving or removing a test:

```ruby
files = Dir.glob('test/{modules,90_1_general,os_stds_methods}/**/test_*.rb').sort
File.write('test/ci_tests.txt', files.map { |f| f.sub(%r{^test/}, '') }.join("\n") + "\n")
```

A single-process run only gives the right answer because every test class name in this tree is
unique. Upstream openstudio-standards reuses class names freely, because its CI runs one file
per process; there, two files declaring the same class are harmless. Here the second definition
would reopen the first and replace its `setup`, and the first file's tests would run with no
fixture. Keep new class names unique.

The second half of the baseline is `test/spec_smoke.rb`, which builds a custom building from a
specification once per registered template, with HVAC off so no sizing run is needed. The
example specification that ships in `create_typical/data/examples` names 90.1 building types
that several templates do not carry, so the smoke builds each template's specification from that
template's own `space_types` table.

The registry holds 60 code templates: 18 in the ASHRAE family and 42 DEER. DEER is kept only
until the Title 24 data replaces it, which is decision D10 in the fork plan and happens on the
`retire_deer` branch in Phase 5. Expect the DEER half of these numbers to disappear then.

## Result

The full suite was measured once, on 2026-09-11, taking 108 minutes:

```
664 tests, 23308 assertions, 10 failures, 11 errors, 10 skips
```

Three of those eleven errors were then fixed: `model_add_exhaust` was ported back from the
deleted prototype file, and two infiltration tests were running with no fixture because of the
duplicate class name described above. Those three, and every test in the classes whose names
were changed, were re-run afterwards and all pass:

```
31 tests, 137 assertions, 0 failures, 1 errors, 0 skips
```

The one remaining error there is `test_reset_equipment`, which fails identically upstream.

So the suite after those fixes stood at 10 failures and 8 errors, all listed below as inherited,
plus the 10 skips.

**That measurement is now out of date and must be repeated.** It was taken while DEER was
removed. D10 brought DEER back, and with it 22 geometry fixtures and every DEER test, so the
suite is larger than the 664 tests above. The failure list below is still believed complete,
because each entry was traced to a cause that DEER does not touch, but the counts are not.
Re-measure end to end before using this as the Phase 4 parity reference.

What has been measured since DEER returned: the restored DEER tests and the tests whose fixture
paths moved, 66 tests with no failures, and the specification smoke across all 60 registered
templates, 48 of which build.

The 12 that do not are the forward-looking plain DEER vintages, 2020 through 2075, which raise
`RuntimeError: This is not a table` from `model_find_objects`. This is inherited: upstream fails
the same templates at the same line. Their ComStock counterparts, `ComStock DEER 2020` and later,
build in both trees, so the fault is in the plain vintages' own data rather than in anything
shared. They all leave in Phase 5 with the rest of DEER.

## Known failures

All of these fail identically on upstream openstudio-standards `str2` at `a31fc0fc3`. Each was
run against that tree rather than assumed, and the numbers match to the digit. None is caused
by the trim, and none should be "fixed" here without first fixing it upstream.

| Test | Symptom | Cause |
|---|---|---|
| `TestEnergyUse`, all 6 | e.g. lighting EUI 8.255 against an expected 8.938 | Hard-coded simulation results that no longer match the current EnergyPlus |
| `TestUnmetHours`, all 7 | 1946.0 against an expected 2013, then nil errors | Same stale expectations; the nil errors come from the class re-running into one directory while the previous results file is still open |
| `test_add_hvac_systems_vav` | three air-source heat pump variants report the annual run failed | EnergyPlus cannot size a hot water reheat coil against a 48.9 C heat pump loop |
| `test_comstock_schedule_mod` | SmallHotel thermostat times not found | Pre-existing in the parametric schedule work |
| `test_create_typical_service_water_heating_deer_school` | one loop, expected more than one | Pre-existing; despite the name this is not DEER removal fallout |
| `test_diurnal_suppresses_overnight_keeps_evening_and_morning` | 0.3457 against an expected floor of 0.4 | Pre-existing in the diurnal schedule work |
| `test_reset_equipment` | seven positional arguments to a keyword-only method | The test was written against an older signature |
| `test_construction_calculated_fenestration_u_factor` | optional not initialized | Pre-existing |

## Known skips

Ten schema tests skip because `json_schemer` is not available inside the OpenStudio CLI. To
validate the specification schema and the example specifications, use `ajv` outside the CLI.

## What the baseline caught

Recorded so the same mistakes are not repeated in later phases.

1. **The port list must scan the tests, not just the library.** `safe_load_model` lived in the
   deleted prototype file and is called by thirty-four kept test files; `model_add_exhaust` is
   a Standard-level shim that ComStock calls. Both were missed because the script that computed
   the Phase 3 port list looked only at `lib/`.
2. **Compare method signatures against upstream after each phase.** Removing NECB quietly took
   the `necb_ref_hp` argument out of six surviving methods. Callers inside `lib` were updated,
   nine test call sites were not. A diff of the parameter lists of every method present in both
   trees found all six and confirmed there were no others.
3. **Restored fixtures belong under `test/`.** The gemspec ships everything under `data/`, so
   putting the twenty-three restored geometry models back in `data/geometry` would have shipped
   13 MB of test input in the gem. They live in `test/models/geometry` instead.
