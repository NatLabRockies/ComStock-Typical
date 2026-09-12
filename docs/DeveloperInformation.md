# Developer Information

## Setup

1. Install [OpenStudio 3.10.0](https://www.openstudio.net/downloads). The CI container is
   `nrel/openstudio:3.10.0`, and the test suite is run with that version.
2. Install the matching Ruby. OpenStudio 3.8.0 and above use Ruby 3.2.2; see the
   [OpenStudio SDK Version Compatibility Matrix](https://github.com/NREL/OpenStudio/wiki/OpenStudio-SDK-Version-Compatibility-Matrix).
   - **Windows**: [Ruby+Devkit 3.2.2](https://rubyinstaller.org/downloads/)
   - **Mac / Linux**: [rbenv](https://github.com/rbenv/rbenv), or your package manager
   - `ruby -v` confirms what you have.
3. Connect Ruby to OpenStudio by creating an `openstudio.rb` in your Ruby installation's
   `site_ruby` directory whose only content is a require of the OpenStudio SDK's own
   `openstudio.rb`. On Windows that is
   `require "C:/openstudio-3.10.0/Ruby/openstudio.rb"` saved to
   `C:/Ruby32-x64/lib/ruby/site_ruby/openstudio.rb`; on Mac,
   `require "/Applications/openstudio-3.10.0/Ruby/openstudio.rb"` saved to
   `/usr/lib/ruby/site_ruby/openstudio.rb`; on Linux, the equivalent under
   `/usr/local/lib/ruby/site_ruby/`.
4. Clone [the repository](https://github.com/NatLabRockies/ComStock-Typical).
5. `gem install bundler`, then `bundle install` from the top level of the clone.

## Running the tests

The tests need the OpenStudio SDK, so run them through the OpenStudio CLI rather than with `ruby`.
One file:

```bash
openstudio execute_ruby_script test/modules/geometry/test_geometry_information.rb
```

The CLI takes about 50 seconds to start, so running the suite file by file spends longer starting up
than testing. `test/baseline_run.rb` loads every kept test file into one process instead:

```bash
openstudio execute_ruby_script test/baseline_run.rb
```

Fifty of the tests run EnergyPlus, and they are most of the suite's runtime. Set
`SKIP_SIMULATION_TESTS` to skip them while iterating on something else:

```bash
SKIP_SIMULATION_TESTS=true openstudio execute_ruby_script test/baseline_run.rb
```

They run by default, skipped tests report as skips rather than passes, and a run with this set is
not a green run. **`test/BASELINE.md`** records what the full suite costs, which failures are
inherited from upstream rather than caused by a change here, and how to check a new failure against
upstream before calling it a regression. Read it before concluding you broke something.

A single-process run only works because every test class name in this tree is unique. Upstream reuses
class names freely, because its CI runs one file per process. Here a second class of the same name
reopens the first and replaces its `setup`, and the first file's tests then run with no fixture. Keep
new class names unique — name the class after its file.

Tests write their run output into a gitignored `output/` directory beside the test file. A new test
that runs a simulation or saves a model should do the same, with `"#{__dir__}/output/…"`.

## Rake tasks

`bundle exec rake -T` lists them:

- `bundle exec rake test:parallel_run_all_tests_locally` — run the test files in `test/ci_tests.txt`
- `bundle exec rake data:update` — regenerate the standards JSONs from downloaded spreadsheets
- `bundle exec rake doc` — generate the API documentation
- `bundle exec rake doc:show` — generate it and open it in a browser
- `bundle exec rake rubocop` — check code style
- `bundle exec rake rubocop:show` — check style and open the report in a browser
- `bundle exec rake build` / `install` / `release` — the standard Bundler gem tasks

The rubocop style file is vendored as `.rubocop-openstudio.yml` so that a style check does not depend
on an external fetch succeeding.

`test/ci_tests.txt` lists the test files, relative to `test/`. Regenerate it after adding, moving or
removing a test — the command is in `test/BASELINE.md`.

## Continuous integration

`.github/workflows/tests.yml` runs every `test_*.rb` under `test/modules`, `test/90_1_general` and
`test/os_stds_methods` in the `nrel/openstudio:3.10.0` container, one file per process, on pushes to
`main` and on pull requests.

## Development process

1. Branch.
2. Modify the code, following the existing structure. See the
   {file:docs/RepositoryStructure.md Repository Structure} and
   {file:docs/CodeArchitecture.md Code Architecture} pages.
3. Add tests. Tests are what stop someone else's change from silently breaking yours.
4. Document the code. This library uses [YARD](https://yardoc.org/); documentation is written inline
   as tagged comments. `bundle exec rake doc` lists what is undocumented.
5. Push the branch and open a pull request.

### Modifying the data

- **90.1 standards data** comes from the
  [building energy standards database](https://github.com/pnnl/building-energy-standards-data).
  Changes belong there.
- **Typical data** — occupancy, ventilation, lighting, schedules, refrigeration and the rest — lives
  in `lib/openstudio-standards/<module>/data/` and is edited here, in the JSON directly.
- **Other standards data** is generated from spreadsheets by `rake data:update`.

The split matters: typical data is vintage-agnostic and describes how a building is used, while
standards data is vintage-specific and describes what was required when it was built. A value that
changes with the code vintage belongs in the standards data, not beside a module.

## Back-porting to and from openstudio-standards

This repository has no shared git history with openstudio-standards, so there is no cherry-picking
between the two remotes. Patches move by `git format-patch` and `git am --3way`, which works because
both trees keep the same `lib/openstudio-standards/` layout. **`BACKPORTS.md`** has the commands,
what is worth sending back, where the two trees have already diverged, and the log of what has been
sent.

## Issues

Issues and feature requests are on the
[repository issues page](https://github.com/NatLabRockies/ComStock-Typical/issues). A failing test is
a thing to fix, not a thing to file.
