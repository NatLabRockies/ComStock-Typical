# ComStock-Typical entry point.
#
# The gem is named comstock-typical, but the library keeps the OpenstudioStandards
# namespace and the lib/openstudio-standards/ directory layout so that fixes patch
# cleanly to and from openstudio-standards (plan D1/D2). The loader itself therefore
# stays at lib/openstudio-standards.rb and this file is the one-line entry point.
require_relative 'openstudio-standards'
