module OpenstudioStandards
  # The HVAC module provides methods create, modify, and get information about HVAC systems in the model
  module HVAC
    # @!group Creator:Coefficients
    # Resolves a typed coefficient set — a performance curve — from a creator spec into an
    # OpenStudio curve object, treating a named reference and a user-entered curve identically.
    #
    # A curve reference is one of:
    # - a user-entered curve object (Hash) giving +type+ and +coefficients+ directly, or
    # - a named reference: a +[source, key]+ pair or a bare name string, resolved against the
    #   curves already in the model (the packaged curve library is a future data-backed source).
    #
    # The user-entered form is built with the shared +HVAC.create_curve_*+ helpers, so every
    # component consumes "typical vs user-specified" curves the same way.
    module Coefficients
      # Curve type => the HVAC.create_curve_* method and whether it accepts y-axis limits.
      CURVE_BUILDERS = {
        'biquadratic' => { method: :create_curve_biquadratic, two_dimensional: true },
        'bicubic' => { method: :create_curve_bicubic, two_dimensional: true },
        'quadratic' => { method: :create_curve_quadratic, two_dimensional: false },
        'cubic' => { method: :create_curve_cubic, two_dimensional: false },
        'exponent' => { method: :create_curve_exponent, two_dimensional: false }
      }.freeze

      # Resolve a curve reference into an OpenStudio curve.
      #
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @param reference [Hash, Array<String>, String] a user-entered curve object, a [source, key]
      #   pair, or a bare curve name
      # @return [OpenStudio::Model::Curve] the curve
      # @raise [ArgumentError] when the reference cannot be resolved
      def self.resolve_curve(context, reference)
        return build_user_curve(context, reference) if reference.is_a?(Hash)

        context.curve_by_name(reference)
      end

      # Build a curve from a user-entered curve object.
      #
      # @param context [OpenstudioStandards::HVAC::BuildContext] the build context
      # @param spec [Hash] the user curve object (type, coefficients, optional limits and name)
      # @return [OpenStudio::Model::Curve] the curve
      # @raise [ArgumentError] when the type is unknown or coefficients are missing
      def self.build_user_curve(context, spec)
        spec = ComponentFactory.symbolize(spec)
        type = spec[:type].to_s.downcase
        entry = CURVE_BUILDERS[type]
        raise ArgumentError, "unknown curve type '#{spec[:type]}'" if entry.nil?

        coefficients = spec[:coefficients]
        raise ArgumentError, 'curve requires coefficients' if coefficients.nil?

        options = {}
        options[:name] = spec[:name] if spec[:name]
        options[:min_x] = spec[:min_x] if spec.key?(:min_x)
        options[:max_x] = spec[:max_x] if spec.key?(:max_x)
        options[:min_out] = spec[:min_out] if spec.key?(:min_out)
        options[:max_out] = spec[:max_out] if spec.key?(:max_out)
        if entry[:two_dimensional]
          options[:min_y] = spec[:min_y] if spec.key?(:min_y)
          options[:max_y] = spec[:max_y] if spec.key?(:max_y)
        end

        OpenstudioStandards::HVAC.public_send(entry[:method], context.model, coefficients, **options)
      end
    end
  end
end
