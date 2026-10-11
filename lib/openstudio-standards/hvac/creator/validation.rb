module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Creator:Validation
    # Structural checks run over a creator spec before anything is built.
    #
    # The point is to fail on the spec, naming the offending path, rather than deep inside a builder
    # with an OpenStudio-level message that says nothing about which entry was wrong. This is not a
    # JSON Schema validator: it checks the structure the factory depends on — section shapes,
    # required keys, the component/setpoint-manager discriminator, registered types, and the build
    # order's backward-reference rule.
    module Validation
      # Top-level array sections, in the order {OpenstudioStandards::HVAC.apply_hvac} builds them.
      # A name may only reference a section at or before its own rank (see the build order in the
      # schema description): a coil on an air loop may name a plant loop, never the reverse.
      SECTION_ORDER = %i[plant_loop_info vrf_info air_system_info doas_info zone_info ems_info].freeze

      # Keys every entry of a section must carry. An air system is the exception: an +existing+
      # retrofit entry resolves a loop already in the model and supplies no components.
      REQUIRED_KEYS = {
        plant_loop_info: %i[name design_info],
        vrf_info: %i[name],
        air_system_info: %i[name],
        doas_info: %i[name air_loops components],
        zone_info: %i[zone_name],
        ems_info: []
      }.freeze

      # Reference keys and the section whose names they may point at.
      REFERENCE_KEYS = {
        plant_loop_name: :plant_loop_info,
        hot_water_loop_name: :plant_loop_info,
        chilled_water_loop_name: :plant_loop_info,
        condenser_loop_name: :plant_loop_info,
        partner_loop_name: :plant_loop_info,
        air_loop_name: :air_system_info,
        cu_name: :vrf_info
      }.freeze

      # Top-level keys that carry spec identity rather than a system to build.
      METADATA_KEYS = %i[schema_version custom_system_type description apply_standard_sizing_and_controls schedules].freeze

      # Cross-loop passes a plant loop declares but that run in their own step, after every loop and
      # zone is built. Their references are therefore not bound by the declaring loop's position: a
      # hot water loop may name the chilled water loop it pairs with even though that loop is listed
      # after it. They are checked at the position of the deferred step itself.
      DEFERRED_PASS_KEYS = %i[two_pipe waterside_economizer supply_water_temperature_control].freeze

      # The deferred passes run after every zone entry and before ems_info.
      DEFERRED_PASS_POSITION = [SECTION_ORDER.index(:zone_info), Float::INFINITY].freeze

      # Check a spec and raise on anything that would build the wrong model or fail obscurely.
      #
      # @param spec [Hash] a deep-symbolized creator spec
      # @return [Array<String>] the warnings raised (already logged by the caller's context)
      # @raise [ArgumentError] listing every structural error found, each with its spec path
      def self.check(spec)
        errors = []
        warnings = []

        spec.each_key do |key|
          next if SECTION_ORDER.include?(key) || METADATA_KEYS.include?(key)

          warnings << "unrecognized top-level key '#{key}'"
        end

        declared = declared_names(spec, errors)
        SECTION_ORDER.each_with_index do |section, rank|
          entries = spec[section]
          next if entries.nil?

          unless entries.is_a?(Array)
            errors << "#{section} must be an array of entries, got #{entries.class}"
            next
          end

          entries.each_with_index do |entry, index|
            path = "#{section}[#{index}]"
            unless entry.is_a?(Hash)
              errors << "#{path} must be an object, got #{entry.class}"
              next
            end

            check_required_keys(section, entry, path, errors)
            check_objects(entry, path, errors)
            check_references(entry, path, [rank, index], declared, errors, warnings)
          end
        end

        raise ArgumentError, "invalid HVAC creator spec:\n  #{errors.join("\n  ")}" if errors.any?

        warnings
      end

      # Map every name a spec declares to its build position: the [section rank, entry index] pair.
      # Entries within a section build in listed order, so the index matters too - a plant loop may
      # not reference a loop listed after it. A secondary loop builds with its primary and so takes
      # the primary's position.
      #
      # @param spec [Hash] the spec
      # @param errors [Array<String>] collected errors, appended to on a duplicate name
      # @return [Hash{String => Array<Integer>}] declared name to build position
      def self.declared_names(spec, errors)
        declared = {}
        SECTION_ORDER.each_with_index do |section, rank|
          entries = spec[section]
          next unless entries.is_a?(Array)

          entries.each_with_index do |entry, index|
            next unless entry.is_a?(Hash)

            collect_names(entry, section, [rank, index], declared, errors)
          end
        end
        declared
      end

      # @return [void]
      def self.collect_names(entry, section, position, declared, errors)
        name = entry[:name]
        if name
          errors << "duplicate name '#{name}' declared in #{section}" if declared.key?(name.to_s)
          declared[name.to_s] = position
        end
        secondary = entry[:secondary_loop]
        collect_names(secondary, section, position, declared, errors) if secondary.is_a?(Hash)
        nil
      end

      # @return [void]
      def self.check_required_keys(section, entry, path, errors)
        required = REQUIRED_KEYS[section] || []
        required.each do |key|
          # An existing air loop is resolved from the model, so it carries a name and nothing else.
          next if section == :air_system_info && entry[:existing] && key != :name

          errors << "#{path} is missing required key '#{key}'" if entry[key].nil?
        end
        nil
      end

      # Walk every nested object in an entry, checking the component/setpoint-manager discriminator
      # and that each type has a registered builder.
      #
      # @return [void]
      def self.check_objects(node, path, errors)
        case node
        when Array
          node.each_with_index { |item, index| check_objects(item, "#{path}[#{index}]", errors) }
        when Hash
          check_discriminator(node, path, errors)
          node.each { |key, value| check_objects(value, "#{path}.#{key}", errors) }
        end
        nil
      end

      # @return [void]
      def self.check_discriminator(node, path, errors)
        has_obj = node.key?(:obj_type)
        has_spm = node.key?(:spm_type)
        if has_obj && has_spm
          errors << "#{path} sets both obj_type and spm_type; an object is one or the other"
          return nil
        end

        if has_obj && !ComponentFactory::COMPONENT_BUILDERS.key?(node[:obj_type].to_s)
          errors << "#{path} has unknown obj_type '#{node[:obj_type]}'"
        end
        if has_spm && !SetpointManagerFactory::SETPOINTMANAGER_BUILDERS.key?(node[:spm_type].to_s)
          errors << "#{path} has unknown spm_type '#{node[:spm_type]}'"
        end
        nil
      end

      # Check that every name reference points backwards in the build order. A name the spec does not
      # declare is a warning, not an error: it may name an object already in the model (an +existing+
      # air loop, a plant loop added before this spec was applied).
      #
      # @return [void]
      def self.check_references(node, path, position, declared, errors, warnings)
        case node
        when Array
          node.each_with_index { |item, index| check_references(item, "#{path}[#{index}]", position, declared, errors, warnings) }
        when Hash
          node.each do |key, value|
            check_reference(value, "#{path}.#{key}", position, declared, errors, warnings) if REFERENCE_KEYS[key] && value.is_a?(String)
            sub_position = DEFERRED_PASS_KEYS.include?(key) ? DEFERRED_PASS_POSITION : position
            check_references(value, "#{path}.#{key}", sub_position, declared, errors, warnings)
          end
        end
        nil
      end

      # @return [void]
      def self.check_reference(name, path, position, declared, errors, warnings)
        target = declared[name]
        if target.nil?
          warnings << "#{path} references '#{name}', which this spec does not declare; it must already exist in the model"
        elsif (target <=> position) == 1
          errors << "#{path} references '#{name}', which this spec builds later (#{SECTION_ORDER[target.first]} " \
                    "entry #{target.last}); a reference may only point backwards in the build order"
        end
        nil
      end
    end
  end
end
