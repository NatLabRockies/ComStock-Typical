# NOT LOADED. openstudio-standards.rb has never required this file, here or upstream, so
# model_economizer_type below does not take effect and ComStock 90.1-2016 and 90.1-2019 use the
# vintage's climate-zone-dependent economizer choice instead. Left as-is deliberately: wiring it
# in would change the economizer on every ComStock model built on these two templates, break the
# bit-for-bit parity measured against openstudio-standards, and leave these two templates
# inconsistent with ComStock 2004-2013, which have no such file. Decide the ComStock economizer
# story before adding the require.
class ComStockASHRAE9012019 < ASHRAE9012019
  # Determine the prototypical economizer type for the model.
  # Defaults to FixedDryBulb based on anecdotal evidence of this being
  # the most common type encountered in the field, combined
  # with this being the default option for many equipment manufacturers,
  # and being the strategy recommended in the 2010 ASHRAE journal article
  # "Economizer High Limit Devices and Why Enthalpy Economizers Don't Work"
  # by Steven Taylor and Hwakong Cheng.
  # https://tayloreng.egnyte.com/dl/mN0c9t4WSO/ASHRAE_Journal_-_Economizer_High_Limit_Devices_and_Why_Enthalpy_Economizers_Dont_Work.pdf_
  #
  # @param model [OpenStudio::Model::Model] OpenStudio model object
  # @param climate_zone [String] ASHRAE climate zone, e.g. 'ASHRAE 169-2013-4A'
  # @return [String] the economizer type.  Possible values are:
  # 'NoEconomizer'
  # 'FixedDryBulb'
  # 'FixedEnthalpy'
  # 'DifferentialDryBulb'
  # 'DifferentialEnthalpy'
  # 'FixedDewPointAndDryBulb'
  # 'ElectronicEnthalpy'
  # 'DifferentialDryBulbAndEnthalpy'
  def model_economizer_type(model, climate_zone)
    economizer_type = 'FixedDryBulb'
    return economizer_type
  end
end
