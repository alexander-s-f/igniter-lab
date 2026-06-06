# frozen_string_literal: true

# igniter-lab/igniter-view-engine/lib/contract_schema_supplement.rb
#
# ContractSchemaSupplement — lab-only overlay layer.
#
# Applies a hand-authored supplement JSON over an extracted ContractSchema,
# adding `item_fields` to array outputs that the compiled contract format
# does not carry (P7 structural gap: Collection[X] names the type but omits
# struct field definitions).
#
# Supplement JSON format (fixtures/schema_supplements/*.json):
#   {
#     "_comment": "...",
#     "_status": "experimental · lab-only · no-canon",
#     "contract_id": "search",
#     "supplements": {
#       "results": {
#         "item_fields": {
#           "id":     { "type": "string",  "required": true  },
#           "score":  { "type": "integer", "required": false }
#         }
#       }
#     }
#   }
#
# Merge rules (compiled output remains authoritative):
#   ALLOWED:   Adding `item_fields` to an existing array output.
#   REJECTED:  Adding item_fields to a non-array output  → :supplement_to_non_array ERROR.
#   REJECTED:  Referencing an output not in compiled schema → :unknown_output_ref WARNING.
#   REJECTED:  Supplement contract_id != schema contract_id  → :contract_id_mismatch ERROR.
#   IGNORED:   Any key other than `item_fields` in a supplement entry (no silent type override).
#
# Diagnostic severity:
#   ERROR:   :contract_id_mismatch    — supplement targets a different contract
#            :supplement_to_non_array — item_fields supplement on a non-array output
#            :invalid_schema          — apply_to received something that is not a ContractSchema
#   WARNING: :unknown_output_ref      — supplement references output absent from compiled schema
#            :unrecognized_supplement_key — supplement entry contains keys other than item_fields
#
# Missing supplement:
#   If no supplement is available (apply_matching with no match), the schema is returned unchanged.
#   SlotTypeLinker will then emit :missing_item_fields_schema for array outputs — P7 behavior preserved.
#
# Does NOT:
#   - Change compiled output port types (scalar types are authoritative from compiled format)
#   - Create new output ports
#   - Change contract_id
#   - Execute contracts or require Igniter::Contract
#   - Make network requests or mutate ViewArtifact
#
# Status: experimental · lab-only · no-canon · no-public-api · no-stable-schema
# Track: lab-igniter-view-contract-schema-supplement-overlay-proof-v0

require "json"
require_relative "contract_schema"

module IgniterView
  class ContractSchemaSupplement
    # ── Diagnostic types ────────────────────────────────────────────────────

    OverlayDiagnostic = Struct.new(:type, :severity, :field, :detail, keyword_init: true) do
      def error?   = severity == :error
      def warning? = severity == :warning

      def to_h
        { type: type.to_s, severity: severity.to_s, field: field, detail: detail }.compact
      end
    end

    # ── Overlay result ───────────────────────────────────────────────────────

    class OverlayResult
      attr_reader :schema, :diagnostics

      def initialize(schema:, diagnostics:)
        @schema      = schema
        @diagnostics = Array(diagnostics).freeze
      end

      def valid?
        @diagnostics.none?(&:error?)
      end

      def errors
        @diagnostics.select(&:error?)
      end

      def warnings
        @diagnostics.select(&:warning?)
      end

      def to_h
        {
          "valid"       => valid?,
          "diagnostics" => @diagnostics.map(&:to_h)
        }
      end
    end

    # ── Supplement data ──────────────────────────────────────────────────────

    attr_reader :contract_id, :supplements

    def initialize(contract_id:, supplements: {})
      @contract_id  = contract_id.to_s
      @supplements  = normalize_supplements(supplements)
    end

    # ── Class-level API ──────────────────────────────────────────────────────

    # Load a supplement from a JSON file.
    # Raises ArgumentError on malformed JSON or missing contract_id.
    #
    # @param path [String, Pathname]
    # @return [ContractSchemaSupplement]
    def self.load_file(path)
      raw  = File.read(path.to_s, encoding: "utf-8")
      data = JSON.parse(raw)
      from_data(data, source: path.to_s)
    rescue Errno::ENOENT
      raise ArgumentError,
            "ContractSchemaSupplement.load_file: file not found: '#{path}'"
    rescue JSON::ParserError => e
      raise ArgumentError,
            "ContractSchemaSupplement.load_file: malformed JSON in '#{path}': #{e.message}"
    end

    # Load all *.json files from a directory.
    # Returns Hash { contract_id (String) => ContractSchemaSupplement }.
    # Logs warnings to stderr for failed loads.
    #
    # @param dir_path [String]
    # @return [Hash { String => ContractSchemaSupplement }]
    def self.load_dir(dir_path)
      supplements = {}
      Dir.glob(File.join(dir_path.to_s, "*.json")).sort.each do |path|
        s = load_file(path)
        supplements[s.contract_id] = s
      rescue ArgumentError => e
        warn "[ContractSchemaSupplement] Skipping #{File.basename(path)}: #{e.message}"
      end
      supplements
    end

    # Build programmatically (for tests / proof runner).
    #
    # @param contract_id [String]
    # @param supplements_hash [Hash] { output_name => { "item_fields" => {...} } }
    # @return [ContractSchemaSupplement]
    def self.build(contract_id, supplements_hash)
      new(contract_id: contract_id, supplements: supplements_hash)
    end

    # Convenience: apply a supplement to a schema.
    #
    # @param schema [ContractSchema]
    # @param supplement [ContractSchemaSupplement]
    # @return [OverlayResult]
    def self.apply(schema, supplement)
      supplement.apply_to(schema)
    end

    # Find the matching supplement (by contract_id) from a Hash map and apply it.
    # If no match exists, returns an OverlayResult with the schema unchanged and
    # no diagnostics (missing supplement is not an error — P7 behavior preserved).
    #
    # @param schema [ContractSchema, nil]
    # @param supplements_map [Hash { String => ContractSchemaSupplement }]
    # @return [OverlayResult]
    def self.apply_matching(schema, supplements_map)
      return OverlayResult.new(schema: schema, diagnostics: []) if schema.nil?

      supplement = (supplements_map || {})[schema.contract_id.to_s]
      return OverlayResult.new(schema: schema, diagnostics: []) if supplement.nil?

      supplement.apply_to(schema)
    end

    # ── Instance: apply this supplement to a ContractSchema ──────────────────

    # @param schema [ContractSchema]
    # @return [OverlayResult]
    def apply_to(schema)
      diags = []

      # Validate input type
      unless schema.is_a?(ContractSchema)
        diags << OverlayDiagnostic.new(
          type:     :invalid_schema,
          severity: :error,
          detail:   "Expected ContractSchema, got #{schema.class}. Supplement not applied."
        )
        return OverlayResult.new(schema: schema, diagnostics: diags)
      end

      # Validate contract_id match — must be exact (case-sensitive per P7 D2)
      if @contract_id != schema.contract_id
        diags << OverlayDiagnostic.new(
          type:     :contract_id_mismatch,
          severity: :error,
          detail:   "Supplement contract_id='#{@contract_id}' does not match " \
                    "schema contract_id='#{schema.contract_id}'. " \
                    "Supplement not applied. contract_id from compiled output is authoritative. " \
                    "Update supplement to use contract_id='#{schema.contract_id}'."
        )
        return OverlayResult.new(schema: schema, diagnostics: diags)
      end

      # Deep-copy existing outputs to avoid mutating the original schema
      merged_outputs = deep_dup_outputs(schema.outputs)

      @supplements.each do |output_name, supplement_def|
        existing = merged_outputs[output_name]

        # Unknown output ref — stale supplement
        if existing.nil?
          diags << OverlayDiagnostic.new(
            type:     :unknown_output_ref,
            severity: :warning,
            field:    output_name,
            detail:   "Supplement references output '#{output_name}' which does not exist " \
                      "in compiled schema for contract '#{@contract_id}'. " \
                      "This may be a stale supplement (contract may have been updated). " \
                      "Supplement entry ignored — no new output port created."
          )
          next
        end

        existing_type = existing["type"].to_s

        # Non-array output — item_fields are not applicable
        if existing_type != "array"
          diags << OverlayDiagnostic.new(
            type:     :supplement_to_non_array,
            severity: :error,
            field:    output_name,
            detail:   "Supplement targets output '#{output_name}' which has type='#{existing_type}' " \
                      "(not 'array'). item_fields are only applicable to array outputs. " \
                      "The compiled output type='#{existing_type}' remains authoritative. " \
                      "Remove this supplement entry or fix the compiled contract."
          )
          next
        end

        # Warn on unrecognized supplement keys (no silent type override)
        unrecognized = supplement_def.keys - ["item_fields"]
        unrecognized.each do |key|
          diags << OverlayDiagnostic.new(
            type:     :unrecognized_supplement_key,
            severity: :warning,
            field:    output_name,
            detail:   "Supplement entry for '#{output_name}' contains unrecognized key '#{key}'. " \
                      "Only 'item_fields' is supported. The key is ignored — " \
                      "supplement cannot override compiled output properties."
          )
        end

        # Apply item_fields to the array output
        item_fields = supplement_def["item_fields"]
        if item_fields.is_a?(Hash) && !item_fields.empty?
          merged_outputs[output_name] = existing.merge("item_fields" => item_fields)
        end
      end

      merged_schema = ContractSchema.build(@contract_id, merged_outputs)
      OverlayResult.new(schema: merged_schema, diagnostics: diags)
    end

    private

    def deep_dup_outputs(outputs)
      (outputs || {}).transform_values do |v|
        v.is_a?(Hash) ? v.dup : v
      end
    end

    def normalize_supplements(supplements)
      return {} unless supplements.is_a?(Hash)

      supplements.transform_keys(&:to_s).transform_values do |v|
        next {} unless v.is_a?(Hash)

        entry = v.transform_keys(&:to_s)
        if entry["item_fields"].is_a?(Hash)
          entry["item_fields"] = entry["item_fields"].transform_keys(&:to_s).transform_values do |f|
            f.is_a?(Hash) ? f.transform_keys(&:to_s) : f
          end
        end
        entry
      end
    end

    def self.from_data(data, source: nil)
      unless data.is_a?(Hash)
        raise ArgumentError,
              "Expected JSON object, got #{data.class}#{source ? " in '#{source}'" : ""}"
      end

      contract_id = data["contract_id"].to_s.strip
      if contract_id.empty?
        raise ArgumentError,
              "Missing or blank 'contract_id' in supplement#{source ? " at '#{source}'" : ""}"
      end

      new(contract_id: contract_id, supplements: data["supplements"] || {})
    end
    private_class_method :from_data
  end
end
