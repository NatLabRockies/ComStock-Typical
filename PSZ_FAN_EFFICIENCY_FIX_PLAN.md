# PSZ fan motor-efficiency fix — plan and progress

**Repo/branch:** `NatLabRockies/ComStock-Typical` → `ccaradon/fix_psz_fan_eff_bug`
**Status:** Option B chosen and implemented (2026-09-14). Data, docstring and tests done;
awaiting a model re-run to confirm the magnitudes in §7.

ComStock-Typical is replacing openstudio-standards as the source of typical-building HVAC, so
the fix lands here. Back-port to openstudio-standards per `BACKPORTS.md` if that tree still
needs it.

---

## 1. Symptom

In ComStock 2025 R3, baseline PSZ/RTU fan energy is **~29% higher** than 2024 R2 for the same
HVAC type and template. It inflates every HP-RTU measure's savings, because those measures
replace the fan.

**All percentages in this document are against CBECS 2018 unless stated otherwise.** R3
national fan electricity is **+29.7%** vs CBECS; correcting the defect brings it to **+8.6%**.
That is *close to but still just above* the CBECS 95% CI, whose upper bound is +7.1%
(556.2 TBtu against a corrected 564.0) — not inside it.

Against our own releases: R2 2024 published 558.1 TBtu of fan electricity over 60.6 B ft²;
corrected R3 is 564.0 TBtu over 64.5 B ft². So the corrected R3 is +1.1% in absolute terms but
**−5.1% in intensity** (8.74 vs 9.21 kBtu/ft²), because non-PSZ fans independently got more
efficient in R3. Relative to CBECS the two releases now agree closely: R2 +7.5%, corrected R3
+8.6%, both marginally above the CI.

## 2. Root cause — proven

`fan_standard_minimum_motor_efficiency_and_size` in
[`lib/openstudio-standards/standards/Standards.Fan.rb`](lib/openstudio-standards/standards/Standards.Fan.rb)
used to do a **two-step** lookup:

1. match the motors bin by brake horsepower,
2. take that bin's `maximum_capacity` as the nominal motor size,
3. **re-look-up at `nominal_hp + 0.01`** to get the next bin up.

Upstream commit
[`fddbdc9ce6dbcc67c320018cbf2e1ec2004dc44e`](https://github.com/NatLabRockies/openstudio-standards/commit/fddbdc9ce6dbcc67c320018cbf2e1ec2004dc44e)
(2025-02-28, "Address comments.", PR #1716 "Building Energy Standards Motors Data Update")
removed step 3 for normal fans. Present through v0.7.1, gone from **v0.8.0** on.
R2 used os-standards 0.5.0; R3 uses 0.8.3. **This fork inherited the post-removal code.**

### Why removing it broke only DOE Ref templates

The DOE Ref motors tables are **the 90.1-2004 table shifted down one bin**, with a `0.290` row
inserted at the bottom:

| bhp bin | 90.1-2004 | DOE Ref 1980-2004 |
|---|---:|---:|
| 0.000–1.000 / 0.000–0.999 | **0.825** | **0.290** ← sentinel |
| 1.001–1.500 / 1.000–1.499 | 0.840 | 0.825 |
| 1.501–2.000 / 1.500–1.999 | 0.840 | 0.840 |
| 2.001–3.000 / 2.000–2.999 | 0.875 | 0.840 |
| 3.001–5.000 / 3.000–4.999 | 0.875 | 0.875 |

Every DOE Ref bin carries the *previous* 90.1 bin's value. Verified: the offset holds for all
19 shared rows, and **"DOE Ref + round-up" returns exactly "90.1-2004 single-step" at every
brake horsepower tested.** The table was authored to be consumed *with* the round-up. The
`0.290` row is a bottom sentinel the round-up always escaped.

Remove the round-up and that sentinel becomes reachable: every sub-1-HP fan in a DOE Ref
template gets motor efficiency **0.29 instead of 0.825**.

Impeller efficiency is 0.65 in both, so total fan efficiency is **0.1885 vs 0.53625** — a
**2.845×** jump in W/cfm (1.56 vs 0.548). Static pressure (622.722 Pa) and CFM/ft² are
unchanged; run hours only +3%.

Corroborating evidence that 0.29 is a fractional-motor value, not a real 0.5 HP motor:
`nrel_zne_ready_2017` and `ze_aedg_multifamily` place 0.29 in a **0.000–0.083 HP** bin (1/12 HP,
shaded-pole) and give 0.700 to 0.083–0.999. The DOE Ref tables never created that split bin.

### The `notes` field settles how the table got this way

Found during implementation, and it qualifies the fix — read before revisiting this. Of the 20
rows in each DOE Ref table, **19 say `"From 90.1-2004 Table 10.8"`** and exactly one says:

> `"Motors below 1 HP assumed to be PSC, with average typical efficiency of 29% per PNNL"`

So the 0.29 row was **deliberately authored**, not a typo. Someone inserted a sub-1-HP PSC
assumption and pushed the 90.1-2004 Table 10.8 series up one bin to make room. With the
round-up in place the insertion had no effect, because the second step always jumped over it —
the motors JSON is byte-identical between os-standards 0.5.0 and 0.8.3, so this row was
unreachable dead data for years before `fddbdc9` activated it.

The result is a table that contradicts itself: the 19 rows still cite 90.1-2004 Table 10.8 but
sit one bin away from what that table actually says (Table 10.8 gives 0.825 for ≤1 HP; the row
labelled 1.0–1.499 claimed 0.825).

**This is the cost of Option B, stated plainly:** it restores those 19 rows to agree with the
source they cite, and in doing so it **drops the PNNL PSC assumption**. The two are mutually
exclusive for the sub-1-HP bin — you can have 90.1-2004 Table 10.8 or a PSC value there, not
both. Option B chooses Table 10.8 because that is what R2 effectively modelled and what the
CBECS comparison validated. If the team wants the PSC assumption back on evidence rather than
by inheritance, that is Option C: a `0.000–0.083` bin at 0.29 with a chosen value for
`0.083–0.999`, argued on its own merits.

### Is 0.29 a real product? Yes — for motors ~10× smaller than where it lands

"Deliberately authored" is not the same as "validated". The row was unreachable for years, so
it never influenced a result until `fddbdc9` activated it; nothing was ever checked against it.

0.29 is a real full-load efficiency — for a shaded-pole or very small PSC motor. The question is
whether the fans receiving it are that size. Parsing every `OS:Fan:OnOff` in the 150 cached R3
models (`compare_fan_029_horsepower_dbtest.py`), 692 of 1,599 fans (43.3%) get 0.29, at these
brake horsepowers:

| band | fans | share | median cfm |
|---|---:|---:|---:|
| **< 1/12 hp** — where the ZNE/AEDG tables put 0.29 | 24 | **3.5%** | 114 |
| 1/12 – 1/4 hp | 243 | 35.1% | 309 |
| 1/4 – 1/2 hp | 261 | 37.7% | 578 |
| 1/2 – 3/4 hp | 108 | 15.6% | 986 |
| 3/4 – 1 hp | 45 | 6.5% | 1,392 |
| > 1 hp | 11 | 1.6% | 1,731 |

Median 0.296 bhp — about a **1/3 HP** motor. **96.5% of the fans receiving 0.29 are larger than
1/12 HP**, the line this repository's own `nrel_zne_ready_2017` and `ze_aedg_multifamily` tables
draw for that value. A 1/3 HP PSC blower is roughly 45–55% efficient; 29% is shaded-pole
territory, an order of magnitude smaller in size class.

The power intensity confirms it independently. Every fan on the 0.29 row runs at
**1.559 W/cfm**, against 0.548 W/cfm for every other fan in the same models. ASHRAE 90.1 allows
roughly 0.8–1.2 W/cfm for small constant-volume systems and metered RTU supply fans typically
land 0.4–0.9 W/cfm — so **all 692 exceed the code allowance for the system they represent**, by
30–95%. The corrected value returns them to 0.548 W/cfm.

### The repository's own PSC data contradicts the 0.29 note

The note says *"PSC, with average typical efficiency of 29% per PNNL."* But this codebase
already carries a PSC curve, in `Standards.Motor.rb`'s `motor_fractional_hp_efficiencies`,
cited to Navigant's 2009 DOE commercial refrigeration report:

| nominal hp | PSC | ECM |
|---|---:|---:|
| ≤ 1/20 | 0.529 | 0.755 |
| ≤ 1/6 | 0.619 | 0.806 |
| ≤ 1/3 | **0.673** | 0.819 |
| ≤ 1/2 | 0.704 | 0.829 |
| ≤ 3/4 | 0.801 | 0.831 |

**PSC never goes below 0.529 anywhere on this curve**, even at 1/20 HP. For the fans actually
receiving 0.29 (median 1/3 HP nominal), the curve says **0.673**. So the 0.29 row contradicts
this repository's own PSC data by a factor of ~2.3, and cannot be defended as a PSC value at
any size. That is the strongest single argument against it.

### The choice of replacement value is second-order

Every defensible candidate lands within ~13 TBtu of the others. The error being fixed is 110.

| sub-1-HP motor efficiency | national fans (TBtu) | vs CBECS |
|---|---:|---:|
| 0.29 — R3 as published | 673.6 | +29.7% |
| 0.673 — PSC curve at 1/3 hp | 577.4 | +11.2% |
| 0.700 — the ZNE/AEDG sub-1-hp row | 574.6 | +10.7% |
| 0.737 — PSC curve, energy-weighted over the affected fans | 571.1 | +10.0% |
| **0.825 — Option B, applied** | **564.0** | **+8.6%** |

None sit inside the CBECS CI (upper bound 556.2). 0.825 is the closest and reproduces R2, which
is why it is the choice; but anyone preferring a PSC-grounded value would land at 0.67–0.74 and
move the national total by only 2%. **Do not spend much on this decision** — the 0.29 row was
the error, and any of these fixes ~90% of it.

### The structural gap worth a follow-up

`Standards.Pump.rb`, `Standards.CoolingTower.rb` and `Standards.FluidCooler.rb` all begin with

```ruby
if nominal_hp <= 0.75
  motor_properties = motor_fractional_hp_efficiencies(nominal_hp, motor_type(nominal_hp))
```

routing fractional motors to the PSC/ECM curve and never touching the motors table there.
**`Standards.Fan.rb` has no such guard** — it uses the fractional path only when
`fan_small_fan?` is true (zone exhaust, fan coil, PTAC/PTHP, PIU terminals), so an ordinary
sub-1-HP supply fan falls through to the motors table.

That asymmetry is the structural reason this bin was ever contested: someone expressing a
fractional-motor assumption had to put it in the motors table, because that is where fans look.
Giving fans the same `nominal_hp <= 0.75` guard would route them to the PSC curve like every
sibling method and make the motors table's sub-1-HP row irrelevant for fans.

**Measured before deciding.** Applying that guard to the audited PSZ models:

| | |
|---|---|
| PSZ fans caught by a 0.75 hp guard | **74%** (1,184 of 1,599) — not an edge case |
| 90.1-2004/07/10 + fixed DOE Ref fans | 1,031 fans, 0.825 → **0.690** |
| 90.1-2013/16/19 fans | 153 fans, 0.855 → **0.685** |
| PSZ fan power | **+4.6%** |
| National fan electricity | 564.0 → **577.1 TBtu**, +8.6% → **+11.2%** vs CBECS |

So it costs about 13 TBtu and moves *away* from CBECS, and most of what it touches is templates
that are already correct. Three further reasons it is not part of this change:

1. **`motor_type` is a stub.** `Standards.Motor.rb` has `def motor_type(nominal_hp); return 'PSC'; end`
   — unconditional. The guard would assign PSC to a 90.1-2019 building's supply fan, dropping it
   0.855 → 0.685, when a modern small RTU fan is the case most likely to be ECM. The curve
   *has* ECM values (0.755–0.831, i.e. close to today's 0.825) but nothing ever selects them.
   **Fixing `motor_type` to choose PSC or ECM by template is the prerequisite**, not optional
   polish — with it, old templates would land near 0.69 and modern ones near 0.82, which is a
   defensible vintage-graded model. Without it the guard just makes every template old.
2. **No validation anchor.** The table fix reproduces R2 exactly and is testable against it.
   The guard is new behaviour with no prior release to compare against; it needs its own
   calibration evidence.
3. **It would confound the re-run.** The table fix has a crisp expected signature (DOE Ref mean
   efficiency 0.397 → 0.559, fan intensity 17.9 → 10.9 kBtu/ft²). Bundling a change that moves
   74% of PSZ fans would smear that, and a surprising result could not be attributed.

Recorded as a follow-up with `motor_type` as its prerequisite.

### Scope: this change also touches pumps, cooling towers and fluid coolers

They read the same `standards_data['motors']`, so the DOE Ref edit shifts their motor
efficiency one bin too — but only above 0.75 bhp, since below that they take the fractional
path. The effect is roughly +1.5 to +2% on those motors in DOE Ref templates. Verified that
**none of them carry a round-up step**, so there is no double-shift risk from the table edit.

### The zoning question, and why it argues for fixing the value

ComStock zoning can produce more and smaller RTUs than the real stock, which would over-populate
this bin. That concern is real and the data supports it: at ~2.5 in w.c. and ~1 cfm/ft², a fan
stays under 1 HP for any zone below roughly 1,650 ft², and the median affected fan moves only
578 cfm (≈1.4 tons) — smaller than a typical real RTU.

But that argues for correcting the efficiency, not for keeping 0.29:

- A punitive efficiency on a bin that is over-populated by a zoning artifact **multiplies the
  artifact** into a 110 TBtu national error, and makes every individual affected building wrong.
- It is not even compensating in the right direction. With 0.29, national fan electricity is
  **+29.7%** against CBECS; corrected it is **+8.6%** — much closer, though still just above the
  CI's +7.1% upper bound.
- The two issues are separable and should stay separate: the motors table should describe real
  motors at the horsepower it is applied to; if zoning creates unrealistically small RTUs, that
  is a zoning fix. Entangling them hides both.

If a residual over-prediction remains after this fix, the remaining **+8.6%** is where to look
for a zoning effect — with the motor table no longer confounding it.

### Why this reads as unintentional

- The method's own docstring still described the round-up: *"This method picks the next nominal
  motor category larger than the required brake horsepower."* That stopped being true. (Its
  worked example was half right — 91.7% is the correct current efficiency for that bin, but the
  stated 7.5 HP nominal is reported as 8, because sizes at or above 2 HP are rounded to whole
  numbers. Both are now corrected.)
- The round-up was added deliberately in PR #82 to follow App G.
- The motors JSON files are **byte-identical** between 0.5.0 and 0.8.3 (6003 bytes). The data
  did not change — only which row is matched.

## 3. Scope — who is affected

Only `ComStock DOE Ref 1980-2004` and `ComStock DOE Ref Pre-1980` have the reachable 0.29 row.
Measured across releases, area-weighted mean total fan efficiency:

| template | R3 area | eff R2 → R3 | Δ |
|---|---:|---|---:|
| **DOE Ref 1980-2004** | 13.39 B ft² | 0.559 → 0.397 | **−0.162** |
| **DOE Ref Pre-1980** | 0.02 B ft² | 0.568 → 0.370 | **−0.198** |
| every `90.1-*` | 10.7 B ft² | ~0.56 → ~0.56 | ≤0.006 |
| every `DEER *` | 2.8 B ft² | ~0.56 → ~0.55 | ≤0.017 |

Affected fans are **zone-HVAC** fans (PSZ-AC, PSZ-HP, PTAC, PTHP, residential AC). Air-system
fans (VAV, PVAV, DOAS) are measured flat between releases and are unaffected — PSZ fans are not
`fan_small_fan?`, so they take the `else` branch and hit the motors table.

Per-fan audit of 288 published models / 3,100 `OS:Fan:OnOff` objects: **25.6% of all PSZ fan
capacity sits at 0.29**, covering 7.5 B ft² (~11.7% of the national stock). Per building:
53.1% none at 0.29, 30.3% partial, 16.6% all.

## 4. Impact if fixed

National, from a per-building-type counterfactual (two independent methods: R3 area × R2
per-template intensity; per-cell blend inversion — agreeing at 105.8 and 113.4 TBtu):

| | R3 as published | corrected | vs CBECS |
|---|---:|---:|---|
| electricity.fans | 673.6 | 564.0 | +29.7% → **+8.6%** |
| electricity.cooling | 755.4 | 734.9 | +125.4% → +119.2% |
| electricity.heating | 244.6 | 247.5 | +60.9% → +62.8% |
| natural_gas.heating | 944.4 | 952.2 | −0.3% → +0.5% |
| site_energy.total | 4989.0 | 4869.6 | +16.6% → **+13.8%** |

Fan reduction **109.6 TBtu (band 84.5–134.9)**. Cooling and heating move because every fan sets
`Motor In Airstream Fraction = 1`; measured couplings per unit fan energy removed are
cooling −0.187, heating elec +0.0266, heating gas +0.0713.

Biggest movers by building type: Retail Stripmall (27.8 TBtu), Warehouse (16.2), Small Office
(14.9), Retail Standalone (14.9).

## 5. Options considered — B was chosen and applied

All three eliminate the 0.29 result. They differ in what replaces it and in the blast radius.

### Option A — restore the two-step round-up

Put step 3 back in `fan_standard_minimum_motor_efficiency_and_size`.

- Reproduces R2 exactly for **all** templates, including the one-bin behaviour.
- **But it also over-credits 90.1 and DEER**, which are not offset tables: at 0.4 bhp, 90.1-2004
  goes 0.825 → 0.840. Those templates are currently correct; this would move them.
- Keeps the latent coupling between method and data — a future table edit can re-break it.

### Option B — un-shift the DOE Ref motors tables *(recommended)*

Data-only change; the method stays single-step. **Do not copy the 90.1-2004 rows** — the tables
are not interchangeable. `doe_ref_*` has exactly one `(4.0, 'Enclosed')` series of 20 rows, its
own bin boundaries, a `notes` field, and a `200–9999` catch-all top row; `ashrae_90_1_2004` has
six pole/type series totalling 113 rows and stops at `150–200`.

The correct edit is mechanical: **each row's `nominal_full_load_efficiency` takes the next row's
current value**; the top catch-all keeps its own. Bins, `notes`, `number_of_poles` and `type`
are untouched. That changes 11 of 20 rows per file:

| row | bhp range | now | → |
|---:|---|---:|---:|
| 0 | 0.000–0.999 | **0.290** | **0.825** |
| 1 | 1.000–1.499 | 0.825 | 0.840 |
| 3 | 2.000–2.999 | 0.840 | 0.875 |
| 5 | 5.000–7.499 | 0.875 | 0.895 |
| 7 | 10.000–14.999 | 0.895 | 0.910 |
| 9 | 20.000–24.999 | 0.910 | 0.924 |
| 11 | 30.000–39.999 | 0.924 | 0.930 |
| 13 | 50.000–59.999 | 0.930 | 0.936 |
| 14 | 60.000–74.999 | 0.936 | 0.941 |
| 15 | 75.000–99.999 | 0.941 | 0.945 |
| 17 | 125.000–149.999 | 0.945 | 0.950 |

Verified: this reproduces the old round-up result at **every** brake horsepower tested
(0.1 → 120 hp), so it restores R2 behaviour for DOE Ref exactly.

- Leaves 90.1 and DEER untouched — no regression where behaviour is already right.
- Deletes the sentinel, so the failure mode cannot recur.
- Cost: it asserts DOE Ref motor efficiencies equal the 90.1-2004 series at the same bhp.
  Defensible — that is what R2 modelled and what CBECS calibration validated — but it *is* a
  modelling call, and Option C is the alternative reading.

### Option C — split the fractional bin, ZNE-style

Give DOE Ref a `0.000–0.083 → 0.29` bin and a `0.083–0.999 → X` bin, mirroring
`nrel_zne_ready_2017`.

- Most faithful to what 0.29 apparently means (shaded-pole fractional motors).
- Requires choosing `X`. 0.825 reproduces R2; 0.78 (the `deer_1985` / `deer_pre_1975` value)
  would encode "older buildings have worse motors" and would *not* reproduce R2.
- Does not by itself fix the one-bin offset in the rows above 1 HP.

**Recommendation: Option B.** It is the only choice that is a pure data fix, reproduces the
behaviour CBECS calibration validated, and leaves correct templates alone. If the team wants
DOE Ref motors to be genuinely worse than 90.1-2004, that is Option C with a chosen `X` and
should be argued on evidence, not inherited from a sentinel.

## 6. Implementation — done 2026-09-14

| step | state |
|---|---|
| Data: one-row efficiency shift in both DOE Ref motors tables | done — 11 rows each, 24 diff lines per file |
| Row 0's `notes` retargeted from the PSC claim to `From 90.1-2004 Table 10.8` | done |
| Docstring rewritten to describe single-step lookup, with the history as a warning | done |
| `nominal_hp = motor_bhp * 1.1` documented as the lookup-failure fallback (it is **not** dead) | done |
| `test/90_1_general/test_fan_motor_efficiency.rb` | done — 7 tests, 64 assertions, all pass |
| Registered in `test/ci_tests.txt` | done |
| Model re-run to confirm §7 magnitudes | **not done** — needs a ComStock run |

**Verification performed**

- *Plausibility:* 96.5% of the fans assigned 0.29 are larger than 1/12 HP, the size class that
  efficiency describes; all of them ran at 1.559 W/cfm against a 0.8-1.2 W/cfm code allowance.
  See §2.

- *Acceptance:* new single-step lookup reproduces the old round-up result at **104 points**
  covering every bin edge, edge+0.0005 and midpoint — **0 mismatches**.
- *Regression capture:* reverting the data to the broken state makes **3 of the 7 tests fail**,
  including the generic guard; restoring it makes all 7 pass. The test genuinely catches this
  bug rather than merely asserting the new numbers.
- Sub-1-HP DOE Ref total fan efficiency is now 0.53625 (was 0.18850) — the 2.845× W/cfm error
  is gone.

**Two things found during implementation that the analysis had wrong**

1. **`nominal_hp` is not dead code.** It is returned when the table lookup fails. Kept and
   documented rather than removed.
2. **90.1 and DEER motors rows are date-effective** (`start_date`/`end_date`), and the lookup
   passes `Date.today`, so one bin can resolve to different efficiencies depending on when the
   code runs — 90.1-2010 at 6.3 bhp is 0.895 before 2010-12-19 and 0.917 after. Any offline
   analysis of these tables that ignores dates will disagree with the model. The DOE Ref tables
   have no date fields. This also means DOE Ref and 90.1-2004 agree away from bin edges but not
   exactly at bhp 30 and 60, where the two tables' bin boundaries differ — expected, not a bug.

### Remaining steps

1. **Re-run a ComStock model set** and confirm the §7 magnitudes.
2. **Regression-check the other templates** in that run — DEER and 90.1 mean fan efficiency
   must not move by more than 0.01.
3. **Log the back-port** in `BACKPORTS.md` if openstudio-standards still needs it. The data
   files sit at the same path in both trees, so `git format-patch` / `git am --3way` applies
   cleanly; the test hunk will need placing by hand, since this fork's test tree has diverged.
4. **Consider the same audit for `nrel_zne_ready_2017` and `ze_aedg_multifamily`.** They still
   carry a `0.000–0.083 → 0.29` row. That one is at least binned for a genuinely tiny motor, so
   it is not the same defect — but it is the only remaining place a sub-0.5 efficiency can be
   returned, and the PSC curve in this same repo says 0.529 even at 1/20 HP, so 0.29 looks
   unsupported there too.
5. **Make `motor_type` vintage-aware (PSC vs ECM), then give `Standards.Fan.rb` the
   `nominal_hp <= 0.75` fractional guard** that Pump, CoolingTower and FluidCooler all have.
   In that order — the guard on today's PSC-only stub costs 13 TBtu and worsens the CBECS
   comparison (§2). This is the real structural fix and deserves its own change and evidence.
6. **Check pump / cooling tower / fluid cooler motors** in the re-run — they share the motors
   table and shift one bin above 0.75 bhp in DOE Ref templates (§2).

## 7. Validation

The fix is right if, on a re-run:

- DOE Ref 1980-2004 PSZ mean total fan efficiency returns to ~**0.559** (from 0.397);
- PSZ baseline fan intensity for that template returns to ~**10.9 kBtu/ft²** (from 17.9 —
  10.6 × 1.03 for the unrelated +3% run hours);
- national fan electricity falls by ~**110 TBtu** (85–135);
- no `90.1-*` or `DEER *` template's mean fan efficiency moves by more than 0.01;
- HP-RTU measure savings fall back toward the R2 deck's $6–8B range.

## 8. Reproduction and references

**Analysis scripts** (in `ComStock/postprocessing/`, gitignored, need `aws sso login`):

| script | produces |
|---|---|
| `compare_fan_baseline_r2_vs_r3_dbtest.py` | baseline fan EUI, pressure, hours by system type |
| `compare_fan_psz_detail_dbtest.py` | PSZ zone-fan parameters |
| `compare_fan_osm_audit_dbtest.py` | downloads published models, parses every `OS:Fan:OnOff` |
| `compare_fan_share_029_dbtest.py` | the per-fan 2×2 — exact share of capacity at 0.29 |
| `compare_fan_heat_coupling_dbtest.py` | the cooling/heating coupling, measured within a release |
| `compare_fan_fix_by_btype_dbtest.py` | per-building-type basis for the correction |
| `compute_fan_fix_btype.py` | the two counterfactuals and the per-type band |
| `compare_fan_029_horsepower_dbtest.py` | **horsepower of the fans receiving 0.29** (no credentials; reads the OSM cache) |

**Public models** (no credentials):
`building_energy_models/upgrade=NN/bldg{id:07d}-up{NN}.osm.gz`.
Affected R3 examples: `45, 46, 48, 339, 345, 347`. Unaffected controls: `37, 39, 40, 41, 42, 343, 344`.

**Full write-up with 12 validated tables:**
`ComStock/postprocessing/output/fan_motor_efficiency_regression_r2_to_r3.md`

**Upstream:** commit `fddbdc9`, PR #1716 (removed it), PR #82 (added it deliberately).
Release stamps: R2 `os_370_stds_050_deer_fixes` / `51a6c20996ff`; R3 `os_3_10_0_stds_0_8_3` / `86d7e215a1`.

## 9. Do not re-test it this way

Comparing baseline end uses **across releases** grouped by `in.hvac_system_type` is confounded
and shows baseline heating *rising* +13.6%, the opposite of the physics. The `PSZ-AC with gas
coil` category gained 2.5 B ft² (16.5 → 19.0) of reassigned buildings between releases, so the
two sides are not the same population. Only a **within-release** comparison holds buildings,
weather and schedules fixed.
