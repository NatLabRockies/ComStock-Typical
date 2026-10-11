# Loads the pre-conversion +create_hvac_system.rb+ under a separate namespace, so the Phase 11
# parity tests compare a composer against the imperative implementation it replaced.
#
# Without this the parity suite is tautological: once a +model_add_*+ method delegates to its
# composer, +model_add_psz_ac+ *is* +Composers.psz_ac+, and comparing the two proves nothing. This
# extracts the file as it stood before the cutover and evaluates it as
# +LegacyHvacReference::HVAC+, leaving the shared component creators and helpers pointing at the
# live module - only the system-creator methods are pinned.
#
# The source comes from git rather than a vendored copy so the reference cannot drift and no large
# duplicate file enters the repository. When the commit is not reachable (a shallow clone, or the
# branch history rewritten), {LegacyReference.available?} is false and the parity tests skip rather
# than fail: a missing reference means "not verified here", not "the composer is wrong".
module LegacyReference
  # The commit the cutover started from - the last state in which every model_add_* method still
  # held its imperative body.
  PRE_CUTOVER_COMMIT = 'hvac-creator-pre-cutover'.freeze
  SOURCE_PATH = 'lib/openstudio-standards/hvac/create_hvac_system.rb'.freeze

  class << self
    # @return [Boolean] whether the pinned legacy implementation could be loaded
    def available?
      load!
      @available
    end

    # @return [String, nil] why the reference is unavailable, for the skip message
    def unavailable_reason
      load!
      @unavailable_reason
    end

    # @return [Module] the pinned legacy HVAC module
    def hvac
      raise "legacy reference unavailable: #{unavailable_reason}" unless available?

      LegacyHvacReference::HVAC
    end

    private

    def load!
      return unless @available.nil?

      source = read_source
      if source.nil?
        @available = false
        warn "legacy_reference: #{@unavailable_reason}; the composer parity tests will skip"
        return
      end

      begin
        # rubocop:disable Security/Eval
        eval(namespaced(source), TOPLEVEL_BINDING, "#{SOURCE_PATH}@#{PRE_CUTOVER_COMMIT}")
        # rubocop:enable Security/Eval
        @available = true
      rescue StandardError, SyntaxError => e
        @available = false
        @unavailable_reason = "could not evaluate the pinned source: #{e.class}: #{e.message}"
        warn "legacy_reference: #{@unavailable_reason}; the composer parity tests will skip"
      end
    end

    def read_source
      repo_root = File.expand_path('../../../..', __dir__)
      source = `git -C "#{repo_root}" show #{PRE_CUTOVER_COMMIT}:#{SOURCE_PATH} 2>&1`
      unless $CHILD_STATUS.respond_to?(:success?) && $CHILD_STATUS.success?
        @unavailable_reason = "commit #{PRE_CUTOVER_COMMIT} is not reachable from this checkout"
        return nil
      end

      source
    end

    # Rehome the module, and with it every self-referential call between the legacy system creators,
    # so a legacy method that builds on another legacy method stays entirely within the reference.
    # Calls to shared component creators and helpers (create_*, kw_per_ton_to_cop, and the rest) keep
    # their OpenstudioStandards:: prefix and resolve to the live module, which is what parity means:
    # the same shared building blocks, assembled the old way.
    def namespaced(source)
      source
        .sub(/\Amodule OpenstudioStandards\b/, 'module LegacyHvacReference')
        .gsub('OpenstudioStandards::HVAC.model_', 'LegacyHvacReference::HVAC.model_')
    end
  end
end
