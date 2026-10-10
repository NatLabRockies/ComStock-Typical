module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Creator:Quantities
    # Resolves dual-unit (IP/SI) input quantities from an HVAC creator spec to SI values.
    #
    # A physical quantity is written in the spec with a unit-suffixed key, for example
    # +supply_temp_f+ or +supply_temp_c+. Each quantity accepts exactly one IP key and one SI
    # key. This module reads the +stem+ (the key without its unit suffix) for a given +dimension+
    # and returns the value in SI. When both unit keys are present they must agree within
    # {TOLERANCE} after conversion, otherwise an error is raised.
    module Quantities
      # Suffix and OpenStudio unit for each supported dimension.
      # Each entry is { ip: [suffix, os_unit] or nil, si: [suffix, os_unit or nil] }.
      # The returned value is always in the SI unit; a nil os_unit means the value is used as-is.
      DIMENSIONS = {
        temperature: { ip: ['_f', 'F'], si: ['_c', 'C'] },
        temperature_difference: { ip: ['_r', 'R'], si: ['_k', 'K'] },
        air_flow: { ip: ['_cfm', 'cfm'], si: ['_m3s', 'm^3/s'] },
        water_flow: { ip: ['_gpm', 'gal/min'], si: ['_m3s', 'm^3/s'] },
        pressure: { ip: ['_inh2o', 'inH_{2}O'], si: ['_pa', 'Pa'] },
        pump_head: { ip: ['_fth2o', 'ftH_{2}O'], si: ['_pa', 'Pa'] },
        capacity: { ip: ['_btuh', 'Btu/h'], si: ['_w', 'W'] },
        power: { ip: ['_bhp', 'hp'], si: ['_w', 'W'] },
        enthalpy: { ip: ['_btu_per_lb', 'Btu/lb'], si: ['_j_per_kg', 'J/kg'] },
        humidity_ratio: { ip: nil, si: ['_kgpkg', nil] }
      }.freeze

      # Maximum allowed relative disagreement between the IP and SI keys of a quantity.
      TOLERANCE = 0.005

      # Resolve a quantity to its SI value.
      #
      # @param hash [Hash] the spec object containing the quantity keys (symbol or string keys)
      # @param stem [String, Symbol] the key without its unit suffix, e.g. 'supply_temp'
      # @param dimension [Symbol] one of the keys of {DIMENSIONS}
      # @param default [Object] value returned when neither unit key is present
      # @return [Float, Object] the SI value, or the default when absent
      # @raise [ArgumentError] when the dimension is unknown, a unit cannot be converted, or the
      #   IP and SI keys are both present but disagree by more than {TOLERANCE}
      def self.resolve(hash, stem, dimension, default: nil)
        spec = DIMENSIONS.fetch(dimension) { raise ArgumentError, "unknown dimension #{dimension.inspect}" }
        si_unit = spec[:si]
        ip_unit = spec[:ip]

        si_val = fetch(hash, "#{stem}#{si_unit[0]}")
        ip_val = ip_unit.nil? ? nil : fetch(hash, "#{stem}#{ip_unit[0]}")

        if !si_val.nil? && !ip_val.nil?
          converted = convert(ip_val, ip_unit[1], si_unit[1])
          unless within_tolerance?(converted, si_val.to_f)
            raise ArgumentError,
                  "conflicting values for '#{stem}': #{ip_val}#{ip_unit[0]} = #{converted} SI " \
                  "disagrees with #{si_val}#{si_unit[0]}"
          end
          return si_val.to_f
        end

        return si_val.to_f unless si_val.nil?
        return convert(ip_val, ip_unit[1], si_unit[1]) unless ip_val.nil?

        default
      end

      # Resolve a required quantity to its SI value, raising when it is absent.
      #
      # @param hash [Hash] the spec object containing the quantity keys
      # @param stem [String, Symbol] the key without its unit suffix
      # @param dimension [Symbol] one of the keys of {DIMENSIONS}
      # @return [Float] the SI value
      # @raise [ArgumentError] when the quantity is not provided
      def self.resolve!(hash, stem, dimension)
        value = resolve(hash, stem, dimension)
        raise ArgumentError, "required quantity '#{stem}' (#{dimension}) not provided" if value.nil?

        value
      end

      # Convert a single value between units using the OpenStudio unit engine.
      #
      # @param value [Numeric] the value to convert
      # @param from_unit [String, nil] the source unit, or nil to skip conversion
      # @param to_unit [String, nil] the target unit, or nil to skip conversion
      # @return [Float] the converted value
      # @raise [ArgumentError] when OpenStudio cannot perform the conversion
      def self.convert(value, from_unit, to_unit)
        return value.to_f if from_unit.nil? || to_unit.nil? || from_unit == to_unit

        result = OpenStudio.convert(value.to_f, from_unit, to_unit)
        raise ArgumentError, "cannot convert #{value} from '#{from_unit}' to '#{to_unit}'" unless result.is_initialized

        result.get
      end

      # Look up a key in a hash tolerating both symbol and string keys.
      #
      # @param hash [Hash] the hash to read
      # @param key [String, Symbol] the key
      # @return [Object, nil] the value, or nil when absent
      def self.fetch(hash, key)
        return hash[key.to_sym] if hash.key?(key.to_sym)
        return hash[key.to_s] if hash.key?(key.to_s)

        nil
      end

      # Whether two values agree within {TOLERANCE} on a relative basis.
      #
      # @param a [Float] first value
      # @param b [Float] second value
      # @return [Boolean] true when the values agree
      def self.within_tolerance?(a, b)
        return true if a == b

        scale = [a.abs, b.abs].max
        return true if scale < 1.0e-9

        ((a - b).abs / scale) <= TOLERANCE
      end
    end
  end
end
