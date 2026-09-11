# Get an additional property from an OpenStudio object as a boolean,
# if no such additional property, then return default value.
# @param component [OpenStudio::Model:Component] the component to get the additional property from
# @param key [String] key string
# @param default [Boolean] the default to return when there is no matching key
# @return [Boolean] boolean value
def get_additional_property_as_boolean(component, key, default = false)
  value = default
  if component.additionalProperties.getFeatureAsBoolean(key).is_initialized
    value = component.additionalProperties.getFeatureAsBoolean(key).get
  else
    OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.utilities', "Cannot find the #{key} in component: #{component.name.get}, default value #{default} is used.")
  end
  return value
end

# Get an additional property from an OpenStudio object as a double,
# if no such additional property, then return default value.
# @param component [OpenStudio::Model::Component] the component to get the additional property from
# @param key [String] key string
# @param default [Integer] the default to return when there is no matching key
# @return [Integer] Integer value
def get_additional_property_as_integer(component, key, default = 0.0)
  value = default
  if component.additionalProperties.getFeatureAsInteger(key).is_initialized
    value = component.additionalProperties.getFeatureAsInteger(key).get
  else
    OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.utilities', "Cannot find the #{key} in component: #{component.name.get}, default value #{default} is used.")
  end
  return value
end

# Get an additional property from an OpenStudio object as a double,
# if no such additional property, then return default value.
# @param component [OpenStudio::Model::Component] the component to get the additional property from
# @param key [String] key string
# @param default [Double] the default to return when there is no matching key
# @return [Double] Double value
def get_additional_property_as_double(component, key, default = 0.0)
  value = default
  if component.additionalProperties.getFeatureAsDouble(key).is_initialized
    value = component.additionalProperties.getFeatureAsDouble(key).get
  else
    OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.utilities', "Cannot find the #{key} in component: #{component.name.get}, default value #{default} is used.")
  end
  return value
end

# Get an additional property from an OpenStudio object as a string,
# if no such additional property, then return default value.
# @param component [OpenStudio::Model::Component] the component to get the additional property from
# @param key [String] key string
# @param default [String] the default to return when there is no matching key
# @return [String] String value
def get_additional_property_as_string(component, key, default = '')
  value = default
  if component.additionalProperties.getFeatureAsString(key).is_initialized
    value = component.additionalProperties.getFeatureAsString(key).get
  else
    OpenStudio.logFree(OpenStudio::Warn, 'openstudio.standards.utilities', "Cannot find the #{key} in component: #{component.name.get}, default value #{default} is used.")
  end
  return value
end
