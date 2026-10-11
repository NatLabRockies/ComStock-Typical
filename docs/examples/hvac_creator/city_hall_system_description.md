# City Hall EER (06/29/2018) — Extracted Sections

Source: `EER_DCAS_City Hall_V1.pdf`

## Space Function Analysis

Loring performed an extensive site survey and categorized the facility's spaces according to their intended use. The total gross square footage for City Hall was verified from drawings obtained from DCAS and is summarized in Table 9.

**Table 9: Building Gross Square Footage by Floor**

| Floor | Approximate Area (sq ft) | Percentage of Building |
|---|---|---|
| Sub-Basement | 1,463 | 3% |
| Basement | 13,479 | 25% |
| First | 12,523 | 23% |
| Second | 12,250 | 22% |
| Third | 15,084 | 28% |
| **Total** | **54,800** | **100%** |

Table 10 presents an estimated breakdown of gross square footage by space use type for the facility. The space areas were considered as part of the retro-commissioning sampling procedures that call for testing in 10% of various spaces.

**Table 10: Approximate Square Footage by Space Use Type**

| Space Type | Approximate Area (sq ft) | Percentage of Building |
|---|---|---|
| Corridor | 9,615 | 18% |
| Multiuse Assembly | 1,674 | 3% |
| Cafeteria | 224 | 0% |
| Mechanical Space | 1,217 | 2% |
| Office | 37,742 | 69% |
| Restroom | 2,024 | 4% |
| Stairwell | 1,114 | 2% |
| Storage | 1,189 | 2% |
| **Total** | **54,800** | **100%** |

Table 11 presents an estimated breakdown of conditioned spaces by space use type for the total facility.

**Table 11: Percent of Conditioned Building Spaces by Space Use Type**

| Space Type | Heated (%) | Cooled (%) | Heated and Cooled (%) | Neither (%) |
|---|---|---|---|---|
| Corridor | - | - | 95% | 5% |
| Multiuse Assembly | - | - | 100% | - |
| Cafeteria | - | - | 100% | - |
| Mechanical Space | - | - | 50% | 50% |
| Office | - | - | 100% | - |
| Restroom | 100% | - | - | - |
| Stairwell | - | - | 100% | - |
| Storage | - | 13% | 70% | 17% |
| **Percent of Total** | **4%** | **0%** | **94%** | **2%** |

### Ongoing/Future Projects

There was no information on any upcoming projects related to the building HVAC systems to the building engineer or the staff. There were no ongoing projects observed during the survey.

## Building Systems Overview

The equipment that is present in the building can be categorized by end-use into the following categories: heating, cooling, domestic hot water, ventilation/exhaust, lighting, kitchen and miscellaneous equipment. Each of these categories and associated systems and subsystems are summarized here and are described in detail in the Mechanical Equipment Inventory found in Appendix 4 and the Lighting Equipment Inventory in Appendix 5. Additionally, Loring performed an analysis of the building envelopes including façade, roofing, and windows. System deficiencies that were encountered during the audit process have been enumerated in the retro-commissioning findings section.

### Heating

The heating demand for the City Hall is provided by the steam to hot water heat exchanger located in the sub-basement of the City Hall. High pressure district steam is received and metered at the Tweed courthouse. The high pressure steam from Tweed Courthouse is staged to low pressure steam. It then splits in two branches — one serving the Tweed courthouse for reheat coils and domestic hot water for the building, and the other serves the City Hall building. At the City Hall, the low pressure steam is further branched to shell and tube heat exchangers for producing hot water utilized for space heating, and also to a steam to hot water heat exchanger to produce domestic hot water.

The steam to hot water heat exchanger (HX SB-01 & HX SB-02) produce hot water for the space heating. The steam supply pressure to the heat exchangers is at 7 psi. The steam supply is controlled by two electronic steam control valves. The control valves are operated based on the temperature sensor located downstream of the supply. There are high limit aqua stat controls to shut the circulation pump in case of sensor failure.

The supply temperature set point of the hot water loop was 180°F at the time of survey. The city water line is connected to provide makeup water for the hot water loop. The heat exchangers were installed in 2015 as a part of major renovation project for City Hall. The heat exchangers were observed to be in fair condition.

There are two hot water circulation pumps (HWP-SB-01 and HWP-SB-02) supplying water to the Air Handling Units (AHUs) and the Fan Coil Units (FCUs). The hot water pumps use 15 HP motors each with variable frequency drives (VFDs). The flow from hot water pumps (VFD speed) is controlled by a differential static pressure sensor located on the third floor. During the survey, it was noted that the hot water circulation pumps were on "Local" mode of operation. The pumps were observed to be operated at 60 Hz speed.

The hot water system is programmed to reset the supply temperature based on the outside air (OA) temperature. The supply temperature reset set points are varied from 180°F at 35°F OA temperature to 125°F at 50°F OA temperatures. The hot water system is programmed to turn on when the OA temperature is 65°F.

There are master steam traps located at the end of drip legs of the heat exchangers. The condensate is returned using condensate return pump and fed to preheat the domestic hot water for the building. The cooled condensate is later drained to the sump pit.

During the renovation project, a condensing boiler system was installed to provide redundancy from the existing district steam system. A new 1,000 MBH condensing boiler with 10:1 turn down ratio was installed. However, according to the building engineer, boiler startup was not conducted because of negative draft issue inside the steam room. The fresh air is introduced in the steam room by an OA supply fan (OASF). During the survey the OASF was noted to be "ON", but there was no air flowing. The OA damper actuator is sequenced to open and close the OA damper with respect to the "ON" and "OFF" operation. The OA dampers inside the duct were observed to be stuck in closed position, which restricts the OA flow in the room. It was observed that the actuator rotates at its position, but does not translate the movement to the damper. This leads to no fresh air intake in the steam room. This probably is the root cause of negative draft inside the steam room when the boiler is operated.

The supply and return piping from the boiler is connected to the existing risers and the hot water loop. The hot water risers serve the fan coil units in all the office spaces, and also to the air handling units located in the attic spaces and sub-basement.

The City Hall also has approximately fifteen (15) unit heaters to provide heating to the storage and mechanical spaces. The unit heaters are provided hot water from the space heating loop. There is also a 12 kW electric air curtain installed in entrance of the basement.

The master outdoor air temperature sensor controlling the HVAC operation for the building is installed on the roof. It was noted that the temperature sensor installation was incorrect. The incorrect installation leads to inaccurate temperature input reading to the BMS.

The space temperature is controlled by the temperature sensors installed in the spaces. The sensors provide feedback to modulate the valves as per the requirements.

### Cooling

The cooling for the City Hall is provided from two sources: one from central chilled water plant at the Manhattan Municipal building and second from the chilled water plant located in the City Hall building itself.

The Chilled water from the Manhattan Municipal building is available during the weekdays from 6 AM through 6 PM in the cooling season. The chilled water is supplied via the dual temperature water loop to Surrogates Courthouse, Tweed Courthouse and the City Hall Campus. Municipal building has one (1) water cooled centrifugal chiller having 310 ton capacity. There are also three (3) 425 ton absorption chillers which are used as backups. The chilled water is supplied using two (2) 60 HP dual temperature water pumps at 44°F. The chilled water is pumped through the loop, and the chilled water pumps located in the City Hall distribute water to the equipment.

For after hours and weekend operations, chilled water is produced in-house using two water cooled chillers. There is a Clima-Cool modular chiller with 100 ton capacity, which was installed in 2015. It has three (3) modules with 15 HP dual compressors for each module. This chiller is primarily used to provide chilled water to the City Hall during after hour chilled water requirements.

The other chiller is a Carrier chiller with 76 ton capacity, and having screw compressors. This chiller was installed in 2010. The chillers are located in Refrigeration room located on first floor and installed in 2015. The chillers were noted to be in fair condition.

There are three (3) 20 HP pumps used for the chilled water circulation and condenser water circulation system. Pump CHWP-B-01 serves dedicatedly the chilled water system, and pump CWP-B-01 serves dedicatedly the condenser water to the building. The third pump CHWP/CWP-B-02 is used to provide redundancy for the chilled water pump or the condenser water pump. The pumps were installed in 2015, and are operated using variable frequency drives.

There are two (2) BAC cooling towers installed on the roof serving the chilled water system in the City Hall building. The cooling tower use 10 HP condenser fans. The cooling towers were installed in 2015. During the survey, a section of the condenser water pipe was observed to be uninsulated near the cooling tower.

There are direct expansion (DX) split air conditioners serving the server rooms, telephone rooms, elevator machine rooms etc. The condensers for the split units are installed on the exterior of the northern perimeter of the building. There are approximately ten (10) total split AC units installed in the building. There are wall mounted and ceiling mounted indoor units. The split units are controlled by wall mounted thermostats located inside the conditioned spaces.

### Domestic Hot Water

The domestic hot water for the building is produced using PVI steam to hot water heat exchanger with a capacity of 73,000 Btu/h. The heater is a semi-instantaneous hot water generator.

The city water is fed to a separate shell and tube heat exchanger to preheat the water. The condensate collected from the space heating heat exchangers is fed to a condensate return tank from which it is supplied to the shell and tube heat exchanger at 145°F, and preheats the city water. The preheated city water is then fed to the PVI steam to hot water heat exchanger.

The condensate return heat recovery is utilized only during the heating season. During the rest of the year, the steam is the only source of domestic hot water.

The hot water is circulated to the building using a ½ HP domestic water circulation pump. The pump is controlled by an aqua-stat. The return water temperature was measured to be 118°F.

### Ventilation & Exhaust

The ventilation inside the City Hall building is provided by the Air Handling Units located in the sub-basement and attic spaces. There are fan coil units installed in the office spaces providing heating and cooling to the tempered air from the air handling units. The fan coil units recirculate the supply air from the air handling units and condition the air as per the space temperature set points. There are fifteen (15) air handling units serving the offices, city council chamber, and other office spaces. There are fourteen (14) return fans associated with the air handling units. The air handling units are designed to provide heating, cooling and humidity controls. Majority of the units are controlled using demand based ventilation. The units are also designed to provide economizer controls. The supply and return fan speeds are controlled using VFDs. There are air flow stations installed on the outside air ducts, return air ducts and supply air ducts to measure air flow.

AHU-SB-01 serving the east side offices is located in the sub-basement. The supply fan is rated for 5 HP and was operated on "Hand" mode and noted to be set at on 43 Hz speed. The return Fan (RF) is rated for 1 HP, and was also operated on "Hand" mode with 12 Hz fan speed. The static pressure switch trips the unit when the access door was opened to conduct functional testing.

There are four (4) AHU's and four (4) RF's serving the basement offices and located in the ceiling spaces. The units were observed in fair condition. The fan belts and bearings were observed to be in fair condition. The filters were observed to be dirty, but the coils were in fair condition.

There are supplemental fan coil units serving the perimeter of the office spaces. These fan coil units have heating and cooling coils with 4 pipe distribution and direct digital controls. The fan coil units are controlled and monitored from the BMS.

The fan coil units installed in the Room 030 and Office 025 located in basement are stand-alone units. They are controlled by programmable space mounted thermostats. Similarly, the fan coil units (Environ-tec) installed in Room 029 (Situation Room) and have individual Creston controllers controlling the space temperature. These fan coil units are not controlled by the BMS, and were installed in 2007. The hot water and chilled water for the fan coil units is supplied from the base building system.

The AHUs and associated return fans are sequenced to be in interlocked operating conditions. The supply fan VFD for AHU-01-EW located in the east attic serving the governors suite was observed on by pass mode, and operating at 100% speed.

During the functional testing of the ventilation system, few of the units were observed to have belt slack, and the filters were observed to be beyond useful life. The fan bearings were observed to be in fair condition. The outdoor air louver serving the AHU-SB-01 located in the sub-basement was observed to be clogged. The louver was clogged with dirt and dry leaves accumulated on the grill section.

The installation of freezestat coil for AHU-WA-03 was observed in poor condition. The freezestat was wound in a corner of the coil section. In general, the freezestat's were observed to be functional for the AHUs.

The AHUs are designed to provide humidity control to the spaces. There are steam humidifier sections installed in the units. The humidifiers were unused during the time of survey.

There are total of fifteen (15) exhaust fans installed throughout the building. There are five (5) toilet exhaust fans, two (2) fans serving the kitchen (food preparation) area, seven (7) exhaust fans serving the copy room, mechanical and electrical rooms and storage spaces and one (1) smoke exhaust fan.

The toilet exhaust fans are controlled by a time clock. The units are scheduled to operate from 6 AM to 11 PM. The exhaust fans serving the other conditioned spaces are interlocked with the supply fans. The unit EF-WA-04 is controlled from the thermostat, and is interlocked with the OA dampers.

### Lighting

The lighting inside the City Hall building primarily uses compact fluorescent lamps (CFL) and the florescent T8 lamps. The lights are controlled on a time schedule — 6 AM to 11 PM from the building management system (BMS).

There are CFL powered lighting fixtures and CFL powered chandeliers in the offices, corridors, restrooms and conference rooms in the first, second and third floors of the building. The lighting fixtures inside the mechanical rooms, storage rooms and locker rooms in sub-basement use F32T8 lamps. Lighting in these spaces is controlled by toggle switches located inside the spaces. The lighting on the basement level is a combination of F32T8 lamps, F28T5 lamps, CFLs, MR16 lamps and F17T8 lamps.

The lighting inside most of the building is original, as the building is a Landmark facility. The lighting inside the offices is controlled using vacancy sensors. The lighting for restrooms, kitchens and conference rooms is controlled using occupancy sensors. The common area lighting inside the building is controlled based on the timed schedule from the BMS.

The lighting located on the exterior of the building is powered by LED (light emitting diode) fixtures. The exterior lighting is also controlled on a timer schedule from the BMS. The lights are programmed to turn on at 5 PM and shut off at 6 AM.

### Miscellaneous & Plug Load Equipment

The miscellaneous plug loads inside the City Hall comprise of office equipment like computers, projectors for conference room, television sets, printers, scanner, copiers, etc. There are a significant number of server racks installed inside the building. The building has a television broadcasting station located in the basement. The building also has radio station equipment installed in the building.

The domestic city water is distributed in the building by a duplex 7.5 HP booster water pump located in the sub-basement. There are two elevators for conveyance. There is a traction elevator serving sub-basement level to second floor of the building. Machine room for this elevator is located on basement level of the building. There is a hydraulic elevator serving 2nd floor to 3rd floor of the building. The machine room for the hydraulic elevator is located on the third floor.

### Onsite Generation

The City Hall uses onsite electric generation from a 100 kW fuel cell, and also from a few solar photo voltaic (PV) modules installed on the roof. The fuel cell utilizes natural gas as the fuel source to generate electricity. The fuel cell was installed in 2016. For Solar PV, there are 38 modules, with a rated capacity of 275 watt per module. The invertor and the batteries supporting the photo voltaic plant are located in the sub-basement electrical room. Electricity generated from the fuel cell and solar PV modules is directly utilized onsite. There is no net metering or provision to send electricity back to the grid.

### Building Envelope

The construction for City Hall started in 1803, and continued over the years with a final completion in the year of 1812. The original building was constructed using brownstone, along with a marble façade. Later the original deteriorated façade was replaced with Alabama limestone during 1954 to 1956. The exterior walls for the building are constructed with masonry and stone structure. The front entrance of the building has stone carved pillars. The front and rear entrance to the building are elevated with a stair case leading to the door. Most recently, the entire building façade repair was undertaken between 2010 and 2015.

The building has wooden framed windows with double pane glass. The windows have clear glass without any coating or film installed. There are five double doors on the front entrance and one double door at the rear entrance of the building. There is a side entrance door at the east side of the building and an emergency exit on west side of the building.

A roof replacement was conducted in recent past. The new roof has a sloped structure with a built up roof construction. The roof is covered by water proofing membrane. The cooling towers and solar photo voltaic panels are installed on the roof.

Loring conducted a thermal survey on the building envelope to identify any infiltration issues. The overall condition of the building envelope was observed to be fair. There were no major instances of infiltration from the window frames or exterior structures. The door sweeps for the exterior doors were observed in poor condition.

## Retro-Commissioning Findings

Loring performed retro-commissioning procedures on the base building system components at City Hall as required by NYC Local Law 87 §28-308.3, including functional testing, creating a list of findings and deficiencies, recommending remediation actions for any deficiencies that are found, and verifying that the deficiencies are corrected. The operations and maintenance staff of the facility was engaged at the start of and during the retro-commissioning process in order to establish the current facility requirements. Recommendations have been made to restore the existing base building systems to proper operation and to identify opportunities for improvement. Retro-commissioning is a process that seeks to improve how building equipment and systems function together. The main purpose of retro-commissioning is to identify and resolve issues that occurred during the design and construction of a building, or address problems that have developed throughout the building's life.

*Note: the source table includes Yes/No/N/A compliance checkboxes rendered as graphics, which were not recoverable by text extraction. Only the item description and the surveyor's comments/findings are reproduced below.*

### Operating Protocols, Calibration and Sequencing

**1.1 HVAC temperature and humidity set points and set backs are appropriate and operating schedules reflect major space occupancy patterns and the current facility requirements.**
- The HVAC temperature and humidity set points were observed to be as per the current facility requirements.
- The HVAC units are programmed to start-up daily with a warm up and cool down modes of operation. The spaces are programmed to maintain 72°F during heating season and 76°F during the cooling season.
- The setback temperatures are programmed to maintain 60°F during heating and 85°F during cooling season.
- The air handling units are scheduled to operate from 5 AM to 11 PM. The fan coil units are operated continuously to maintain the space temperature.

**1.2 HVAC sensors are properly calibrated.**
- The HVAC sensors including the temperature sensors, air flow measurement station, and carbon dioxide sensors were verified to be calibrated.
- The freezestat's for the air handling units were functionally tested to verify the operation.
- The outside air temperature sensor was observed to be installed incorrectly.
- The temperature sensor for AHU-01-EW was noted to be malfunctioned. This disables the economizer function for the AHU.
- *Related: RCM No. 08 Re-arrange the Outside Air Temperature Sensor; RCM No. 03 Repair HVAC Controls*

**1.3 HVAC controls are functioning and control sequences are appropriate for the current facility requirements.**
- The VFD controls for some of the air handling unit fans were observed to be on bypass mode. The supply and return fans for AHU-SB-01, RF-SB-01 and AHU-01-EW were operating on bypass.
- The chilled water control valve for some of fan coil units were observed to be 100% open from the BMS during the survey in heating season. The chilled water valves were observed to be open for FCU-B-12, B-13, B-15, B-17, B-19, B-09, 2-10, 2-15.
- The VFDs for hot water circulation pump HW-SB-01 was observed to be in bypass mode.
- The damper for the outside air fan serving the condensing boilers was observed to be stuck. The actuator was observed to be functional.
- The freezestat for AHU-WA-03 was noted to be wound and placed in one corner.
- *Related: RCM No. 02 Repair Outside Air Dampers for Boiler; RCM No. 03 Repair HVAC Controls; RCM No. 10 Re-arrange the Freezestat Distribution*

**1.4 Loads are distributed equally across equipment when appropriate (i.e. fans, boilers, pumps, etc. that run in parallel).**
- The building HVAC systems were observed to be capable of handling the building heating and cooling loads.
- Systems operating in parallel (pumps, cooling towers, etc.) appeared to have equal load distribution.

**1.5 Ventilation rates are appropriate for the current facility requirements.**
- The ventilation rates were measured for the air handling units serving the offices. The ventilation rates were observed to be as per the current facility requirements.
- Spot measurements for the carbon dioxide (CO2) rates were conducted at various locations (see Appendix 2 for CO2 levels at various spaces). The CO2 rates were found acceptable for all locations measured.

**1.6 Systems automatic reset functions are functioning properly, if applicable.**
- The VFD for the hot water circulation pump HWP-SB-01 was observed to be operating in bypass mode.
- The VFDs for some of the supply fans and return fans were observed to be operating in bypass mode.
- *Related: RCM No. 03 Repair HVAC Controls*

**1.7 Adjustments have been made to compensate for oversized or undersized equipment so that it is functioning as efficiently as possible.**
- The facility has appropriately sized equipment, and the equipment is functioning as per the design intent.

**1.8 Simultaneous heating and cooling does not occur unless intended.**
- There were no instances of simultaneous heating and cooling noted in the building.

**1.9 HVAC system economizer controls are properly functioning, if applicable.**
- The economizer controls were noted to be not operational for AHU-01-EW.
- The temperature and enthalpy set points were verified for the operation of economizer controls for other systems.
- *Related: RCM No. 03 Repair HVAC Controls*

**1.10 The HVAC distribution systems, both air and water side, are balanced.**
- None of the Air Handling units are serving more than 10,000 ft² of building area.
- The hydronic system was observed to be balanced as per the design documents.

**1.11 Light levels are appropriate to the task.**
- The light levels were tested to be appropriate as per the current facility requirements.
- A sample set of light levels at various locations were measured throughout the building to verify the light levels.

**1.12 Lighting sensors and controls are functioning properly according to the occupancy, schedule, and/or available daylight, where applicable.**
- The lighting inside the offices, server rooms and storage spaces is controlled by automatic lighting sensors. The common areas including the corridors, restrooms, city council chamber, bull pen etc. are operated based on a time schedule programmed at the BMS.

**1.13 Domestic hot water systems have been checked to ensure proper temperature settings.**
- The domestic hot water temperatures were noted to be as per the current facility requirement. The return hot water temperature was measured to be 118°F.

**1.14 Water pumps are functioning as designed.**
- The hot water pump HWP-SB-01 (15 HP) was observed to be operated in manual mode of operation at 40 Hz speed.

**1.15 System water leaks have been identified and repaired.**
- There was a water leak observed at the heat recovery loop for the DHW system.
- *Related: RCM No. 05 Fix Water Leaks*

### Cleaning and Repairs

**2.1 HVAC equipment (vents, ducts, coils, valves, soot bin, etc.) is clean.**
- The outdoor air louver serving the AHU-SB-01 was observed to be clogged with leaves and dirt.
- The coil section for AHU-01-EW was observed to be dirty.
- *Related: RCM No. 01 Ventilation System Cleaning*

**2.2 Filters are clean and protocols are in place to replace, as appropriate.**
- The filters for the HVAC equipment located in the attic were observed to be close to the end of their useful life.
- *Related: RCM No. 06 Replace Dirty Filters and Implement Replacement Protocol*

**2.3 Light fixtures are clean.**
- The lighting fixtures were observed to be neat and clean. There is a protocol to clean the fixtures every summer.

**2.4 Motors, fans and pumps, including components such as belts, pulleys and bearings, are in good operating condition.**
- The fan belt tension for a few of the supply fans was observed to be incorrect. The supply fans for AHU-WA-03, AHU-W-01 and AHU-01-EW have belt slack.
- *Related: RCM No. 09 Adjust Fan Belt Tension*

**2.5 Steam traps have been replaced as required to maintain efficient operation, if applicable.**
- The steam traps were tested in the steam room located in the sub-basement. The tested traps were in fair condition.

**2.6 A protocol for addressing the issues which necessitate manual overrides on existing equipment has been developed.**
- A protocol to address the remediation of manual overrides has been developed.

**2.7 Boilers have been tuned for optimal efficiency, if applicable.**
- Start-up for the new condensing boiler has not been conducted, and the boiler could not be tested for combustion efficiency.

**2.8 Exposed hot and chilled water and steam pipes three (3) inches or greater in diameter with associated control valves are insulated in accordance with the standards of the New York City energy conservation code as in effect for new systems installed on or after July 1, 2010.**
- The steam supply pipe to the steam to hot water heat exchanger for the DHW was observed to be uninsulated.
- The DHW header pipe was observed to be uninsulated.
- *Related: RCM No. 04 Replace Damaged or Missing Insulation*

**2.9 In all easily accessible locations, sealants and weather stripping are installed where appropriate and are in good condition.**
- The door sweeps for the exterior doors were observed to be worn out.
- *Related: RCM No. 07 Install Door Sweeps for Exterior Doors*

### Training and Documentation

**3.1 Permits for all HVAC, electrical and plumbing equipment are in order.**
- Permits for all HVAC, electrical and plumbing equipment are available at the facility.

**3.2 Critical operations and maintenance staff have received appropriate training, which may include labor/management training, on all major equipment and systems and general energy conservation techniques.**
- The building engineers and the building operations staff have required training and certificates.
- The building staff has required knowledge and expertise to operate and perform required maintenance on all major equipment in the building.

**3.3 Operational and maintenance record keeping procedures (log books, computer maintenance records, etc.) have been implemented.**
- Log books are maintained to keep records of operating procedures and conditions of HVAC equipment.

**3.4 Operations and maintenance manuals are on site and accessible to the operators.**
- The operations and maintenance manuals are on site and accessible to the operators.

**3.5 Maintenance contracts are on site and accessible to the operators.**
- Majority of the maintenance is conducted in house for the HVAC equipment.
- There are maintenance contracts on site for services outsourced, easily accessible to the operators.

**3.6 The most recent retro-commissioning reports are on site and accessible to the operators.**
- Retro-commissioning has not been performed at City Hall building prior to this report.
