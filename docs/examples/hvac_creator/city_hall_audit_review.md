# City Hall EER — facts beyond the system description, and what they mean for the spec

Companion to `city_hall_hvac_spec.json` and `city_hall_system_description.md`.
Source: the rest of `EER_DCAS_City Hall_V1.pdf` (facility description, energy-use narrative, RCx
measures, O&M, and Appendices 2–5 and 10). ECM proposals, savings, and the audit's own modeling
are deliberately excluded; only facts about the building as it exists (including deficiencies the
retro-commissioning measures require to be corrected) are recorded.

Three sections:

1. **Refinements the current spec can take** — supported by `hvac_creator_schema.json` today.
2. **Facts EnergyPlus can model but the HVAC creator cannot express** — candidate schema/factory work.
3. **Facts outside HVAC** — loads, envelope, generation, schedules; modelable in EnergyPlus, out of the creator's scope.

A fourth section lists conflicts between parts of the report.

---

## 1. Refinements the spec can take now

### 1.1 Plant pumps (Appendix 4 inventory; body text agrees)

| Tag | Duty | Motor | Flow | Head | Model | Observed |
|---|---|---|---|---|---|---|
| HWP-SB-01 / -02 | HW circulation (lead/standby) | 15 HP | 420 GPM | 70 ft | B&G 1510 BFW 9 | VFD bypassed, manual at 40 Hz; DP bypass valve 75% open; DP sensor DPT-1 on 3rd floor |
| CHWP-B-01 | CHW | 20 HP | 500 GPM | 75 ft | B&G 1510 4BC | VFD 49% (Sep 2017) |
| CWP-B-01 | CW | 20 HP | 500 GPM | 75 ft | B&G 1510 4BC | VFD 60% |
| CHWP/CWP-B-02 | shared standby | 20 HP | 500 GPM | 75 ft | B&G 1510 4BC | VFD 15% |

Spec change: `pump_head_fth2o` 70 (HW) / 75 (CHW, CW); add `pump_flow_gpm` 420 / 500 / 500.
(The Appendix 10 checklists print the HW and CHW nameplates swapped — 20 HP/500 GPM for HW and
15 HP/420 GPM for CHW; the inventory and the body text both say 15 HP HW / 20 HP CHW+CW.)

### 1.2 Hot water plant

- Two steam-to-HW heat exchangers HX-SB-01/02, B&G SU-106-2, **3,208 lb/hr steam each**
  (≈ 3.0 MMBtu/h each at ~950 Btu/lb; ≈ 6.1 MMBtu/h total). Spec change: give the
  `DistrictHeatingWater` source `capacity_btuh` ≈ 6,100,000, or split it into two parallel branches
  of ≈ 3,050,000 each to mirror the two exchangers.
- District steam arrives at 160–180 psi, is reduced at the Tweed Courthouse PRV station, and
  reaches the exchangers at 10 psi (7 psi per the body text); 8" LPS main, 4" branch to the space
  heating HXs, 3" to the DHW HX.
- **AHU heating coils are designed for a 30 °F ΔT** (ECM 3 existing conditions); the loop was
  measured at only 10 °F ΔT because the pumps run in manual at 40 Hz with the bypass open. Spec
  change: `temp_delta_r` 30 on the Hot Water Loop and `lwt_f` 150 on the AHU heating coils (the
  spec currently uses 20 R / 160 °F).
- Hot water produced at 180 °F at the survey (confirms the setpoint in the spec).
- Condensate: duplex return pumps CRU-SB-01/02 (2 × 2 HP, 30 GPM); condensate leaves at 145 °F
  and preheats DHW feed water through HX-SB-03 (B&G WU-67-44, 1,250 MBH) during the heating season.
- Condensing boiler EB-SB-01: Lochinvar SBN-1000, **941 MBH output, 94.1 % thermal efficiency**,
  natural gas connection in place, never commissioned (negative draft; its OA supply fan
  OASF-SB-01's damper is stuck closed — RCM 02). Still not modeled; see §2.4 for why.
- Steam traps: 9 in the facility (8 F&T, 1 thermostatic), 6 tested, 0 failed.

### 1.3 Chilled water plant

- CH-B-01 ClimaCool UCW030AHASACMPX, 100 tons, three modules (2 × 15 HP compressors each),
  water-cooled, 2015. CH-2 Carrier 30HX076R, 76 tons, 2010 (30HX is a screw machine; one
  checklist calls it reciprocating). Both in the basement refrigeration room; glycol is in the loop.
- Measured (Sep 2017): CHWS **46.9 °F**, CHWR 57.0 °F, ΔT 10.1 °F; module kW/ton 0.34 / 0.36 /
  0.18; Carrier 0.12 kW/ton at 123 tons (implausible — the meter values are unreliable); total
  plant 95.7 kW at 305 tons.
- Cooling towers CT-R-01/02: BAC VTL-103-K, **103 tons nominal each, one cell, forced draft, belt
  drive, VFD fan**, 10 HP. Measured 87 °F in / 80 °F out (7 °F range). "System capable of free
  cooling" per the checklist — but no waterside economizer is described anywhere.
- Spec is consistent (variable-speed towers, 100/76-ton water-cooled chillers). Optional changes:
  chiller `chw_flow_gpm` ≈ 149 per module / 292 for the Carrier as measured; tower
  `design_range_temp_r` 10 stays (7 measured under part load).
- Municipal Building plant that supplies the dual-temperature loop: one 310-ton water-cooled
  centrifugal chiller (213 kW nameplate ≈ 0.69 kW/ton), three 425-ton absorption chillers as
  backup (rarely used), two 60 HP dual-temperature pumps (VFDs at 40 Hz), two 200 HP condenser
  pumps, a 450-ton six-cell tower; chilled water at 44 °F, **May–October, weekdays 6 AM–6 PM**;
  City Hall is 12.5 % of the loop's served area (54,800 of 437,431 ft²). See §2.1.

### 1.4 Air handling units — the full inventory

Appendix 4 supply/coil data, ECM 2 design outdoor air, Appendix 10 fan nameplates and observed
VFD speeds (Feb 2018 unless noted). All units: Trane or Mafna, "recirculation" type, HW heating
coil, CHW cooling coil, DDC, 2015, pleated **MERV 8** filters changed quarterly.

| AHU | Location | Serves | Supply CFM | Htg MBH | Clg MBH | SF HP | RF (HP / CFM) | Design OA CFM | Observed SF / RF Hz |
|---|---|---|---|---|---|---|---|---|---|
| AHU-SB-01 (multizone) | Sub-basement SB06 | East side offices | 3,555 | 124 | 181 | 5 | RF-SB-01 1 / 2,225 | 1,800 | 43 / 25 (locked) |
| AHU-B-01 | Basement clg Rm 032 | Rms 032, 034, 035 | 800 | 55 | 44 | 0.75 | 0.5 / 750 | 380 | — |
| AHU-B-02 | Basement clg Rm 022 | Rms 020–024, 131 | 1,950 | 96.3 | 96.5 | 1.5 | 0.5 / 750 | 900 (via OASF-B-02, 1,900 CFM) | — |
| AHU-B-03 | Basement clg Rm 020 | (Rm 032 printed) | 1,820 | 94 | 107 | 1 | 0.75 / 1,740 | 1,820 (100 % OA, via OASF-B-03 1,620 CFM) | — |
| AHU-B-04 | Basement clg 012 | Rms 012–016 (NYPD) | 830 | 52.3 | 42 | 0.75 | RF-SB-02 0.5 / 700 | 240 (via OASF-SB-01, 1,000 CFM) | — |
| AHU-01 "existing" | 1st fl Rm 121 | Rm 121 | — | — | — | 3 | none | ~450 | — |
| AHU-3-04 | 3rd fl Rm 304 | Rms 300–305 | 1,250 | 50 | 77.8 | 3 | 0.5 / 1,000 | 1,250 | — |
| AHU-EA-05 | East attic 310 | Council Chamber Rm 203 | 8,000 | 130 | 257 | 10 | 3 / 5,400 | 1,000 | 27 / 28 (Nov) |
| AHU-EA-06 | East attic 310 | Council Chamber Rm 203 | 8,000 | 162 | 257 | 10 | 2 / 5,400 | 1,400 | 15 / 15 (Nov) |
| AHU-EA-07 | East attic 310 | Council lounge Rm 211 | 3,000 | 75 | 147 | 5 | 1.5 / 2,800 | 800 | — |
| AHU-02-EE | East attic 311 | Governor's suite east | — | — | — | 2 | 1 / — | ~250 | — |
| AHU-01-EW | West attic 315 | Governor's suite west | — | — | — | 2 | 1 / — | ~250 | 60 / 60 (bypass) |
| AHU-WA-01 | West attic 313 | Bullpen Rm 204 | 4,000 | 130 | 173 | 7.5 | 2 / 3,600 | 1,500 | 36 / 38 |
| AHU-WA-02 | West attic 313 | C.O.W. Rm 208 | 2,400 | 62.5 | 102.2 | 3 | 1 / 2,200 | 1,020 | 36 / 38 |
| AHU-WA-03 (multizone) | West attic 313 | Blue Room 127, vestibule 130 | 1,810 | 94.4 | 101.4 | 3 | 1.5 / 1,740 | 1,250 | 43 / 37 |
| **Totals** | | | **37,415** (12 units) | **1,125** | **1,586** (≈132 tons) | **57.5** | 12 RFs, 28,305 CFM | **14,310** | |

Mapping onto the spec's two loops (zones are by space function, so this is the best split):

- **Assembly AHU** ≈ EA-05 + EA-06 + EA-07 + WA-01 (council chamber, lounge, bullpen):
  23,000 CFM supply, 4,700 CFM design OA, 497 MBH heating, 834 MBH cooling, 32.5 HP supply fans.
- **Office AHU** ≈ everything else: ≈ 14,400 CFM supply (+ three units with no CFM listed),
  9,610 CFM design OA, 628 MBH heating, 752 MBH cooling, 25 HP supply fans.

Spec changes: `design_info.des_supply_airflow_cfm` and `des_outdoor_airflow_cfm` per loop;
`ventilation.min_oa_flow_cfm` 9,610 / 4,700; `CoilHeatingWater.capacity_btuh` 628,000 / 497,000
(cooling coils have no capacity key — see §2.5). Fan pressure rise: 57.5 HP over 37,415 CFM is
1.15 W/CFM total; the spec's 4.0 in. H2O at 0.6 efficiency ≈ 0.78 W/CFM supply plus 1.0 in. return
is consistent with the nameplates. If the model is ever re-zoned by AHU, the table above gives
per-loop values directly.

Observed operation worth reflecting in controls:

- **Supply air temperatures in heating season were 67–77 °F** (SB-01 71.5, WA-01 67–68, WA-02
  74.5, WA-03 75, 01-EW 76.6; EA-06 80 °F on preheat in Nov) — the AHUs deliver neutral-to-warm
  air in winter, not 55–65 °F. AHU-EA-05 was delivering 51 °F air the same day (council chamber
  cooling on 85 % OA). Spec change: replace the `Warmest` 55–65 °F manager with an
  `OutdoorAirReset` supply setpoint (≈ 75 °F at 30 °F OA → 55 °F at 70 °F OA), which the schema
  supports and which reproduces the observations; keep `des_heat_sat_f` ≈ 75.
- Mixed air 47–68 °F with OA dampers 41–92 % open at 28 °F outdoors: the units run far above
  minimum OA in winter (dampers "sequenced on space occupancy"; measured OA 2–4× code minimum on
  every tested unit — SB-01 2,428 vs 900 required; WA-01 1,462 vs 400; WA-02 622 vs 500; WA-03 125
  vs 149–171; 01-EW 674 vs 213). Using the ECM 2 design OA as the controller minimum (above)
  captures this better than code minimums.
- Return air 71–74 °F confirms the 72 °F occupied heating setpoint.
- VFD speeds 25–72 % on modulating units (EA-06 at 15 Hz) — the 0.3 minimum flow fraction on the
  VAV terminals is reasonable; AHU-SB-01 and AHU-01-EW were locked (RCM 03 requires restoring
  static-pressure control, which is what the spec models).
- Economizer: sequences "tested" on all units; AHU-01-EW's was not auto-enabled (failed TS-1
  mixed-air sensor). High-limit type is still not stated anywhere.
- OA is drawn through dedicated outdoor-air supply fans on the three basement units
  (OASF-SB-01 1,000 CFM → AHU-B-04; OASF-B-02 1,900 → AHU-B-02; OASF-B-03 1,620 → AHU-B-03).
  Expressible as an `oa_components` fan on the OA stream; only meaningful if those units get
  their own loop.

### 1.5 Fan coil units

- **95 FCUs**: basement 21 (Trane FCAB0601 A), 1st floor 44 (FCAB0601 B), 2nd floor 19
  (FCAB0601 A), 3rd floor 11 (FCKB0301G, a smaller cabinet); all ¼ HP, DDC, 2015. Several serve
  **corridors** (FCU-1-23/24/42/43 on the 1st floor, FCU-3-10/11 on the 3rd). Spec change: give
  the Corridor zone a four-pipe fan coil too (it currently has only the AHU terminal).
- **15 stand-alone FCUs** on the west side of the basement (Office #8, Rooms 030, 033, 022; Environ-tec
  units in Room 029 with Crestron controllers, installed 2007) are not on the BMS, run on wall
  thermostats, and their fans run continuously in both seasons including unoccupied hours.
  `ConstantFanVariableFlow` with an always-on availability already represents this.
- Chilled-water valves on FCU-B-09/12/13/15/17/19 and FCU-2-10/15 were 100 % open from the BMS
  in heating season (RCM 03) — a control fault, see §2.6.

### 1.6 Unit heaters

15 units, all **Trane S-A18, 14.2 MBH at 1 GPM, 500 CFM**: sub-basement mechanical/corridor/storage
(UH-SB-01..04), basement refrigeration room (UH-0-01), west attic (6), east attic (4). Spec change:
`max_airflow_cfm` 7,000 on the Mechanical Space unit heaters (14 units) and 1,000 on Storage; a
coil capacity (199 MBH / 28 MBH) can be given through an explicit `components` list with
`CoilHeatingWater.capacity_btuh`.

### 1.7 Exhaust fans (all Greenheck, DDC, 2015)

| Duty | Fans | Total CFM | Zone in the spec | Control noted |
|---|---|---|---|---|
| Toilet exhaust | TX-3-01 1,165; TX-3-02 400; TX-WA-01 175; TX-WA-02 200; TX-WA-03 500 | **2,440** | Restroom (spec has 2,000) | time clock 6 AM–11 PM |
| Kitchenettes | TF-B-01 200; TF-B-02 200 | **400** | Cafeteria (spec has 1,000) | interlocked with supply fans |
| Copy rooms | EF-SB-02 200; EF-WA-03 230 | 430 | Office / Storage | interlocked |
| Basement office rooms 025–030 | EF-WA-01 1,060 | 1,060 | Office | interlocked |
| "Existing AHU" Rm 121 | EF-WA-02 1,320 | 1,320 | Office | interlocked |
| Cellar storage | EF-SB-01 850 | 850 | Storage (spec has 500) | interlocked |
| Refrigeration machine room | EF-WA-04 700 | 700 | Mechanical Space | thermostat, interlocked with OA dampers |
| Elevator machine room | EF-3-05 200 | 200 | Mechanical Space | — |
| Smoke exhaust | SMEF-3-01 275 | 275 | not modeled | — |

Spec changes: Restroom 2,440 CFM; Cafeteria 400; Storage ≈ 1,050 (850 + copy 200); Mechanical
Space 900 (700 + 200); add ≈ 2,600 CFM of coupled exhaust to the Office zone (EF-WA-01/02/03).
Total exhaust 7,675 CFM against 14,310 CFM design OA — the building is strongly positive.

### 1.8 Split DX units (ten, 216 kBtu/h ≈ 18 tons total)

AC-1..3 Mitsubishi PKA-A18GA 18 kBtu/h (server room), AC-4 18 kBtu/h (pantry), AC-5 24 kBtu/h
(elevator machine room, 2010), AC-6/7 24 kBtu/h (utility electrical & UPS room C-7; AC-7 is a
Liebert), AC-8/9 24 kBtu/h (broadcasting room), AC-10 24 kBtu/h (council server room). Spec change:
give the Mechanical Space packaged unit an explicit `CoilCoolingDXSingleSpeed` with
`rated_capacity_btuh` 216,000. These rooms carry 24/7 server loads (§3.2) — if a "Server Room"
zone is ever added, this equipment and roughly 24 kW of rack load belong there, not in Mechanical
Space.

### 1.9 Door air curtain

DOC-B-01 at the basement entrance: 1/5 HP fan, **8 kW electric heater** (the body text says
12 kW). EnergyPlus has no air-curtain object; if wanted, an electric `ZoneHVACUnitHeater`
(`components` with `CoilHeatingElectric.capacity_w` 8000) in the Corridor zone is the nearest
supported stand-in.

---

## 2. Modelable in EnergyPlus, not expressible in the creator

### 2.1 District chilled water available only weekdays 6 AM–6 PM, May–October
The single most consequential gap. EnergyPlus (24.1+) `DistrictCooling` has a *Capacity Fraction
Schedule*; OpenStudio exposes it (`DistrictCooling::setCapacityFractionSchedule`). The creator's
`districtObj` has no schedule key, so the spec cannot say "this source is off after 6 PM and on
weekends", and under `SequentialLoad` the district source will carry the whole load year-round.
Candidate schema/factory addition: `capacity_fraction_sch_name` on `districtObj` (and on
`DistrictHeatingWater` for symmetry). Until then the on-site chillers never run in the model.

### 2.2 Plant equipment operation schemes
Beyond `load_distribution_scheme`, EnergyPlus can stage sources by load range
(`PlantEquipmentOperation:CoolingLoad`) or by outdoor conditions, which is how "district first,
Clima-Cool for after-hours, Carrier as second stage" would normally be expressed. Not in the schema.

### 2.3 Hot water loop lockout above 65 °F outdoor air
Done in the spec with EMS (`Plant Loop Overall` / `On/Off Supervisory`). EnergyPlus also offers
`AvailabilityManager:HighTemperatureTurnOff` on a plant loop, which the creator applies only as
part of `two_pipe` changeover. A `plantLoop.availability` OAT lockout (high/low turn-off managers)
would make this declarative.

### 2.4 Installed-but-idle equipment
The 941 MBH condensing boiler exists on the loop but has never run. EnergyPlus would keep it off
through the operation scheme (2.2) or a zero-capacity scheme entry; `BoilerHotWater` has no
availability schedule. No way to declare "present, sizing_factor 0, never dispatched".

### 2.5 Cooling coil capacity
`coilCoolWaterObj` carries design flows and temperatures but no capacity; the inventory gives
1,586 MBH of AHU cooling coils. `CoilCoolingWater` in EnergyPlus is UA-based (design flows and
temperatures size it), so this is expressible only indirectly — `water_flow_gpm` / `air_flow_cfm`
with the measured 46.9 / 57 °F water and design air temperatures.

### 2.6 Documented faults (as-found vs. as-corrected)
The RCMs require correction, so the spec models the corrected building. EnergyPlus can model the
as-found state with `FaultModel:*` objects, none of which the creator exposes:

| As-found condition | EnergyPlus fault object |
|---|---|
| Master OA temperature sensor mis-installed (shield upside down; operator overrides the BMS reading); AHU-01-EW TS-4 out of calibration | `FaultModel:TemperatureSensorOffset:OutdoorAir` |
| Mixed-air sensors TS-1 miscalibrated on AHU-SB-01 (47 vs 55 °F) and AHU-01-EW (failed, −22.9 °F) | `FaultModel:TemperatureSensorOffset:MixedAir` |
| AHU-01-EW economizer not enabled | `FaultModel:EconomizerFault` / `FaultModel:TemperatureSensorOffset:ReturnAir` |
| AHU-01-EW RH sensor HS-1 out of calibration | `FaultModel:HumiditySensorOffset:*` |
| Dirty coils (SB-01, 01-EW, WA-01) and dirty filters (EA-05, WA-01, WA-02) | `FaultModel:Fouling:Coil`, `FaultModel:Fouling:AirFilter` |
| Airflow stations out of calibration (SB-01, WA-01/02/03) | no direct object (DCV/OA flow sensor bias) |
| HW pumps in manual at 40 Hz with bypass 75 % open; AHU-SB-01 fans locked 43/25 Hz; AHU-01-EW at 100 % | constant-speed pump/fan at fixed fraction (schedule-driven flow), no fault object |
| Eight FCU chilled-water valves 100 % open in heating season | EMS actuator on the coil/valve; no fault object |
| Belt slack (WA-01, 01-EW), freezestat misplaced (WA-03), tripped static switch (SB-01) | not modelable |

### 2.7 Pipe heat loss
Uninsulated sections found: 15 ft of 3" DHW, 15 ft of 3" steam, 10 ft of 8" CHW header (chiller
room), 3 ft of 4" condenser water (roof, beside CT-2); a leaking condensate-recovery HX header.
`Pipe:Indoor` / `Pipe:Outdoor` model these; the creator only places adiabatic pipes.

### 2.8 Ventilation requirements per space type (Appendix 3)
`DesignSpecification:OutdoorAir` and `People` objects carry these; the creator references a
`design_oa_name` only on ideal-loads equipment.

| Space type | Required OA | Occupant density (per 1,000 ft², as printed) |
|---|---|---|
| Corridor | 0.06 cfm/ft² | 0 |
| Multiuse Assembly | 7.5 cfm/person + 0.06 cfm/ft² | 100 |
| Cafeteria | 7.5 cfm/person + 0.18 cfm/ft² | 100 |
| Mechanical Space | N/A | 7 |
| Office | 5 cfm/person + 0.06 cfm/ft² | 5 |
| Restroom | 70 cfm/fixture exhaust | 0 |
| Stairwell | N/A | 150 (sic) |
| Storage | N/A | 100 (sic) |

All space types: occupied 5 AM–11 PM winter and summer, 72 °F heating / 76 °F cooling design,
humidity control "Yes" at 50 % RH (humidifiers exist but are unused), DHW 120 °F at restrooms.

### 2.9 Humidity control
AHUs have steam humidifier sections (unused); the facility requirement says 50 % RH. A
`HumidifierSteamElectric` plus a `SingleZoneHumidityMinimum` manager and a `humidistat` are all in
the schema, so this is expressible if the humidifiers are ever put back in service; nothing to add
for the as-found state.

---

## 3. Facts outside HVAC (EnergyPlus-modelable; out of the creator's scope)

### 3.1 Occupancy and schedules
- ~125 regular occupants; up to ~200 during council meetings, press conferences, receptions.
- Business hours 8 AM–6 PM, after-hours meetings to 8 PM; building open 24/7 with NYPD present;
  peak occupancy Mon–Fri 8–6, Sat/Sun 8–4. AHUs and exhausts 5 AM–11 PM every day; lighting
  time-scheduled 6 AM–11 PM from the BMS; exterior lights 5 PM–6 AM.
- 24/7 conditioned spaces: NYPD locker room (basement, AHU-B-04), the mayor's situation room,
  server/telecom/broadcast rooms, press-conference rooms and "important offices" held at setback
  (60 °F / 85 °F) to be ready for events; warm-up and cool-down modes daily.
- BMS: Honeywell SymmetrE.

### 3.2 Plug and process loads (Appendix 4)
150 computers @ 75 W (11.3 kW); 10 TVs @ 200 W (2 kW); **30 server racks @ 800 W (24 kW)**;
miscellaneous 20 kW; radio station (1st floor) 30 kW; TV broadcasting station (basement) 30 kW;
printers/scanners printed as "101330 W each" (10 @ 1,330 W = 13.3 kW is the likely reading).
≈ 130 kW connected — about 2.4 W/ft², and consistent with the 217 kW metered electric baseload.
Elevators: traction 30 HP (sub-basement to 2nd), hydraulic 25 HP (2nd to 3rd). Domestic booster
pumps 2 × 7.5 HP; duplex sump 2 × 3 HP.

### 3.3 Lighting (Appendix 5; per-row CSV available)
Interior connected **36,468 W** (0.67 W/ft²), 885 fixtures: CFL 11.5 kW, T5 7.5 kW, chandeliers
6.1 kW (44 fixtures, 14 W/lamp), T8 5.6 kW, MR16 4.0 kW (80 × 50 W), LED 1.2 kW (mostly 112 × 9 W
council-chamber spots plus 44 × 5 W exit signs), incandescent 0.24 kW. Exterior 10 × 78 W LED,
4,732 h/yr. Controls by connected watts: toggle switches 25.0 kW, occupancy sensors 4.2 kW, panel
(24/7 corridors, stairs, exit signs) 3.8 kW, vacancy sensors 2.6 kW (1st-floor executive rooms),
timers 0.8 kW. The appendix gives annual hours per row (8,760 h for circulation and exit signs;
3,120 h council chamber and 2nd-floor ceremonial rooms; 2,080 h most offices; 1,040 h
mechanical/storage; 500 h situation room) but no daily profiles and no room areas.

### 3.4 Domestic hot water
PVI Quick Draw steam-fired semi-instantaneous heater, **730 MBH, 690 lb/hr steam at 5 psi**,
year-round (the only steam use May–September); city water preheated by condensate through
HX-SB-03 (1,250 MBH) in the heating season only; ½ HP (inventory: ⅓ HP, 10 GPM, 20 ft) recirculation
pump on an aquastat; storage tank and restroom delivery measured 118 °F against a 120 °F requirement.

### 3.5 Envelope
1803–1812 masonry with Alabama limestone facade (1954–56, repaired 2010–15); wood-framed
double-pane clear windows, no film; sloped built-up roof with waterproofing membrane (recent);
ceiling heights "significantly higher than a normal office". Infiltration: worn or missing door
sweeps on all 15 exterior doors (five front double doors, one rear, east side entrance, west
emergency exit) and worn weather stripping on the basement door (RCM 07); thermal survey found no
major window/frame leakage. Landmark status forbids facade changes.

### 3.6 On-site generation
100 kW natural-gas fuel cell (installed 2014 per the energy narrative, 2016 per the systems
overview; ~54,300 therms/yr of gas is essentially all fuel cell); 38 × 275 W = **10.45 kW** rooftop
PV with inverter and batteries in the sub-basement electrical room. The systems overview says all
generation is used on site with no net metering; the gas narrative says the fuel cell output "is net
metered". EnergyPlus: `Generator:FuelCell` / `Generator:PVWatts` with an `ElectricLoadCenter`.

### 3.7 Utilities and metering
Two Con Edison electric meters; one gas meter; steam metered only at Tweed Courthouse (City Hall
taken as 30 % of the shared meter, ~2,059 Mlbs/yr); chilled water from the Municipal Building is
unmetered. 2014–16 averages: 1,623,937 kWh/yr (adjusted), 54,313 therms, 2,059 Mlbs steam; site EUI
146 kBtu/ft²-yr (81 on the EPR, which excludes the district chilled water and fuel-cell gas).

---

## 4. Conflicts within the report

| Item | Values | Likely resolution |
|---|---|---|
| HW vs CHW pump nameplates | Inventory + body: HW 15 HP/420 GPM/70 ft, CHW/CW 20 HP/500 GPM/75 ft; Appendix 10 checklists: swapped | Inventory and body text |
| Low-pressure steam at the HXs | 7 psi (systems overview), 10 psi (ECM 8), 5 psi (DHW heater) | 7–10 psi space heating, 5 psi DHW |
| Air curtain heater | 12 kW (systems overview), 8 kW (inventory) | inventory |
| Fuel cell install year | 2016 (systems overview), "early 2014" (energy narrative) | unresolved |
| Fuel cell net metering | none (systems overview) vs net metered (gas narrative) | unresolved; no export either way |
| RF-SB-01 locked speed | 12 Hz (systems overview), 25 Hz (RCM 03, checklist) | 25 Hz (two sources) |
| Carrier chiller type | screw (systems overview; 30HX is a screw), reciprocating (checklist) | screw |
| OA temperature 49.4 °F "sensor" reading on every AHU on two different test dates | carried-over form value | ignore |
| Measured OA per AHU | Appendix 2 and Appendix 10 differ (checklist "measured" equals Appendix 2 "normal use") | use "normal use" as the operating value |
| Unit heater fan "16 W (500 CFM)" | typo in the inventory | 500 CFM is the usable value |
| Appendix 8 Energy Star statement, Appendix 9 floor plans | scanned images, no text | not extracted |
