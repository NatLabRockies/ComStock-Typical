# Back-ports to openstudio-standards

ComStock-Typical has no shared git history with
[openstudio-standards](https://github.com/NatLabRockies/openstudio-standards) — it was created
as a fresh snapshot of that repository's `str2` branch (decision D1 in the fork plan). There is
no common ancestor, so there are no cross-repo pull requests and no `git cherry-pick` between
the two remotes.

What makes back-porting work instead is that both repositories keep the same
`lib/openstudio-standards/` directory layout. As long as a file sits at the same path in both,
a patch applies in either direction:

```bash
# in ComStock-Typical
git format-patch -1 <sha> --stdout > /tmp/fix.patch

# in openstudio-standards
git am --3way /tmp/fix.patch
```

## What is worth sending back

openstudio-standards keeps its own `create_typical` frozen at the `develop` state for existing
OpenStudio measures, and the two copies are expected to diverge (decision D8). So the changes
worth back-porting are the ones in code both repositories still share:

- the base `Standard` class (`lib/openstudio-standards/standards/standard.rb` and
  `Standards.*.rb`);
- the ASHRAE 90.1 template family and its data;
- module-level fixes that openstudio-standards' own `create_typical` still depends on.

Typical-layer work that only exists here — the space type refactor, parametric schedules, the
HVAC creator, Title 24 — is fork-only by design and is not back-ported.


## Where the trees have already diverged

`lib/openstudio-standards/` is the shared surface and is where a patch applies in either
direction. The test tree is not: Phases 1–3 gave the kept tests their own fixtures under
`test/models/` (upstream reads them from `test/doe_prototype/`, `test/deer_prototype/`,
`test/90_1_prm/` and `data/geometry/`, none of which exist here), so a patch that touches both
a library file and its test usually needs the test hunk placed by hand.

Two library signatures also differ, because the NECB removal took the `necb_ref_hp` parameter
with it: `coil_dx_find_search_criteria`, `coil_{cooling,heating}_dx_single_speed_standard_minimum_cop`,
`coil_{cooling,heating}_dx_single_speed_apply_efficiency_and_curves` and
`model_apply_hvac_efficiency_standard` each lost that argument here.

## Defects worth raising upstream

Found here, but present in openstudio-standards too, so they are upstream's to fix rather than
ours to diverge on.

- **Five 90.1 override files are never required.** `openstudio-standards.rb` requires
  `nrel_zne_ready_2017.ZoneHVACComponent` and `ze_aedg_multifamily.ZoneHVACComponent` but not the
  2013, 2016 or 2019 ones, so `zone_hvac_component_vestibule_heating_control_required?` falls
  through to the base implementation and vestibule heating control is never applied for those
  three vintages. The two `comstock_ashrae_90_1_*.AirLoopHVAC.rb` files are unrequired for the same
  reason, so their flat `FixedDryBulb` economizer never takes effect. **This fork has wired in the
  three vintage files and deliberately left the two ComStock ones unloaded**; see the note at the
  top of each. Upstream is unchanged either way.

## Log

Record every patch sent upstream, so the two trees can be reconciled later.

| Date | ComStock-Typical commit | Upstream PR | What it fixes |
|---|---|---|---|
| _(none yet)_ | | | |
