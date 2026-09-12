# ComStock-Typical

ComStock-Typical is a Ruby gem that extends the {https://www.openstudio.net/ OpenStudio SDK} with
methods for creating **typical** commercial building energy models. It is a fork of
{https://github.com/NREL/openstudio-standards openstudio-standards}, trimmed to the typical-building
path that {https://github.com/NREL/ComStock ComStock} uses.

It has two main use-cases:

1. **Create a typical building model** — geometry, space types, loads, schedules, ventilation,
   service water heating, refrigeration, exterior lighting and HVAC — from user geometry, from
   programmatically generated geometry, or from a custom building specification.
2. **Apply code-minimum performance** to a model from the standards data: envelope constructions,
   HVAC efficiencies, fan and pump power, lighting power, and so on.

A typical building is not a code-compliance artifact. It follows minimally code-compliant equipment
efficiencies for its vintage because that is what buildings of that vintage tend to have, but its
purpose is to represent the existing stock, not to determine code. The DOE/PNNL prototype buildings,
which do determine code, are not created here; they stay in openstudio-standards.

## What this fork does not do

Prototype building creation, Appendix G / PRM baseline generation, the NECB, BTAP, CBES, OEESC and
IECC standards, construction costing, and the OpenStudio Application library export were all removed.
They remain in openstudio-standards. The standards that remain here are the ASHRAE 90.1 family and
DEER, and DEER is kept only until the California Title 24 data replaces it.

## Overview of Main Features

For a high-level overview of what the library does, see the {file:docs/Features.md Features page}.

## User Quick Start Guide

If you are a user, see the {file:docs/UserQuickStartGuide.md User Quick Start Guide}.

To build a model of your own mix of space types, see the
{file:docs/CustomBuildings.md Custom Buildings page}.

## Developer Information

If you are a developer looking to get started, see the
{file:docs/DeveloperInformation.md Developer Information page}.

For an overview of the repository structure, see the
{file:docs/RepositoryStructure.md Repository Structure page}.

For an overview of the code architecture, see the
{file:docs/CodeArchitecture.md Code Architecture page}.
