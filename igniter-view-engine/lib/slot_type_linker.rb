# frozen_string_literal: true

# igniter-lab/igniter-view-engine/lib/slot_type_linker.rb
#
# SlotTypeLinker — lab-only static analysis layer.
#
# Validates a ViewArtifact's slot declarations against a set of ContractSchema
# objects, producing typed diagnostics for:
#
#   ERROR level (fail closed — view linkage is invalid):
#     :unresolved_contract_ref     — slot from: "x.y" but no schema for contract "x"
#     :missing_output_ref          — schema for "x" exists but has no output "y"
#     :slot_type_mismatch          — slot type != contract output type
#     :missing_required_item_field — required contract item field absent from node_params_schema
#     :non_array_collection_slot   — collection slot's contract output is not type=array
#
#   WARNING level (allowed, but surfaced for developer awareness):
#     :item_field_type_mismatch    — param type != contract field type (display rules still run)
#     :extra_item_field            — contract item field not in node_params_schema (silently ignored)
#     :missing_item_fields_schema  — contract array output has no item_fields defined
#
# The linker is an optional post-compilation step. It does NOT:
#   - Execute contracts or fetch data
#   - Mutate the ViewArtifact or its digest
#   - Change SSR or JS runtime behavior
#   - Require any network access
#
# Usage:
#   schemas = ContractSchema.load_dir("fixtures/contract_schemas/")
#   result  = SlotTypeLinker.link(artifact, schemas)
#   result.valid?         # → true/false (false if any :error diagnostic)
#   result.errors         # → [LinkageDiagnostic, ...]
#   result.warnings       # → [LinkageDiagnostic, ...]
#   result.diagnostics    # → all diagnostics
#
# Status: experimental · lab-only · no-canon · no-public-api · no-stable-schema
# Track: lab-igniter-view-slot-contract-type-linkage-proof-v0

module IgniterView
  # ── Diagnostic value object ──────────────────────────────────────────────

  LinkageDiagnostic = Struct.new(
    :type, :severity, :slot, :collection, :detail,
    keyword_init: true
  ) do
    def error?   = severity == :error
    def warning? = severity == :warning

    def to_h
      {
        type:       type.to_s,
        severity:   severity.to_s,
        slot:       slot,
        collection: collection,
        detail:     detail
      }.compact
    end
  end


  # ── LinkageResult ────────────────────────────────────────────────────────

  class LinkageResult
    attr_reader :artifact, :diagnostics

    def initialize(artifact:, diagnostics:)
      @artifact    = artifact
      @diagnostics = Array(diagnostics).freeze
    end

    # True when no error-severity diagnostics are present.
    # Warnings do not make the result invalid.
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


  # ── SlotTypeLinker ───────────────────────────────────────────────────────

  class SlotTypeLinker
    # Separator between contract_id and output_name in the from: path.
    # e.g. "search.results" → contract_id="search", output_name="results"
    SEPARATOR = "."

    def self.link(artifact, schemas)
      new(artifact, schemas).link
    end

    def initialize(artifact, schemas)
      @artifact = artifact
      @schemas  = (schemas || {}).transform_keys(&:to_s)
      @diags    = []
    end

    # Run all slot linkage checks and return a LinkageResult.
    def link
      return LinkageResult.new(artifact: @artifact, diagnostics: []) if @artifact.nil?

      (@artifact.slots || {}).each do |slot_name, slot_def|
        link_slot(slot_name, slot_def)
      end

      LinkageResult.new(artifact: @artifact, diagnostics: @diags.dup)
    end

    private

    # ── Per-slot resolution ──────────────────────────────────────────────

    def link_slot(slot_name, slot_def)
      contract_ref = slot_def["contract_ref"].to_s
      return if contract_ref.empty?

      sep_idx = contract_ref.index(SEPARATOR)
      if sep_idx.nil?
        add_error(:unresolved_contract_ref, slot: slot_name,
                  detail: "from: '#{contract_ref}' has no '.' separator — " \
                          "expected 'contract_id.output_name'")
        return
      end

      contract_id = contract_ref[0, sep_idx]
      output_name = contract_ref[(sep_idx + 1)..]

      schema = @schemas[contract_id]
      if schema.nil?
        add_error(:unresolved_contract_ref, slot: slot_name,
                  detail: "No ContractSchema registered for contract_id '#{contract_id}' " \
                          "(from: '#{contract_ref}'). " \
                          "Available: #{@schemas.keys.map { |k| "'#{k}'" }.join(", ")}")
        return
      end

      output_def = schema.output(output_name)
      if output_def.nil?
        add_error(:missing_output_ref, slot: slot_name,
                  detail: "Contract '#{contract_id}' has no declared output '#{output_name}'. " \
                          "Declared outputs: #{schema.outputs.keys.map { |k| "'#{k}'" }.join(", ")}")
        return
      end

      # Validate slot declared type vs contract output type
      validate_slot_type(slot_name, slot_def, output_def)

      # For collection slots, validate item field compatibility
      contract_type = output_def["type"].to_s
      if contract_type == "array"
        validate_collection_linkage(slot_name, slot_def, output_def)
      end

      # If a collection references a non-array slot → error
      if contract_type != "array" && collection_slot?(slot_name)
        add_error(:non_array_collection_slot, slot: slot_name,
                  detail: "Slot '#{slot_name}' is used by a collection but contract output " \
                          "type='#{contract_type}' (expected 'array')")
      end
    end

    # ── Type validation ──────────────────────────────────────────────────

    def validate_slot_type(slot_name, slot_def, output_def)
      declared_type = slot_def["type"].to_s
      contract_type = output_def["type"].to_s
      return if declared_type.empty? || contract_type.empty?
      return if types_compatible?(declared_type, contract_type)

      add_error(:slot_type_mismatch, slot: slot_name,
                detail: "Slot '#{slot_name}' declared type='#{declared_type}' but " \
                        "contract output type='#{contract_type}'")
    end

    # ── Collection item field validation ─────────────────────────────────

    def validate_collection_linkage(slot_name, _slot_def, output_def)
      collections_for_slot(slot_name).each do |coll_name, coll_def|
        item_element_name = coll_def["item_element"].to_s
        item_element      = @artifact.element(item_element_name)
        next if item_element.nil?

        node_params_schema = (item_element.node_params_schema || {})
        item_fields        = output_def["item_fields"]

        if item_fields.nil? || item_fields.empty?
          add_warning(:missing_item_fields_schema, slot: slot_name, collection: coll_name,
                      detail: "Contract array output '#{slot_name}' declares no item_fields — " \
                              "cannot validate element '#{item_element_name}' param compatibility")
          next
        end

        validate_item_fields(slot_name, coll_name, item_element_name,
                             node_params_schema, item_fields)
      end
    end

    def validate_item_fields(slot_name, coll_name, elem_name, node_params_schema, item_fields)
      # 1. Check required contract fields present in node_params_schema
      item_fields.each do |field_name, field_def|
        required        = field_def["required"] == true
        in_schema       = node_params_schema.key?(field_name)

        if required && !in_schema
          add_error(:missing_required_item_field, slot: slot_name, collection: coll_name,
                    detail: "Contract item field '#{field_name}' is required=true but " \
                            "not declared in element '#{elem_name}'.node_params_schema. " \
                            "Display rules referencing this field will evaluate nil.")
        end

        # 2. Type compatibility check (warning only — display rules still evaluate)
        if in_schema && field_def["type"]
          contract_field_type = field_def["type"].to_s
          declared_param_type = node_params_schema[field_name].to_s
          unless types_compatible?(declared_param_type, contract_field_type)
            add_warning(:item_field_type_mismatch, slot: slot_name, collection: coll_name,
                        detail: "Field '#{field_name}' in element '#{elem_name}': " \
                                "node_params_schema declares type='#{declared_param_type}' " \
                                "but contract item_fields type='#{contract_field_type}'. " \
                                "Display rules will receive the value as-is.")
          end
        end
      end

      # 3. Extra fields in node_params_schema not in contract item_fields (warning)
      # Policy: ALLOWED — extra params may be provided by the host independently.
      # Display rules referencing them will evaluate nil if the contract doesn't supply them.
      node_params_schema.each_key do |param_name|
        next if item_fields.key?(param_name)
        add_warning(:extra_item_field, slot: slot_name, collection: coll_name,
                    detail: "Element '#{elem_name}' declares param '#{param_name}' which " \
                            "is not in contract item_fields. This param is allowed — " \
                            "it may be provided by host independently, or display rules " \
                            "referencing it will evaluate nil.")
      end
    end

    # ── Helpers ──────────────────────────────────────────────────────────

    def types_compatible?(a, b)
      return true if a.empty? || b.empty?
      return true if a == "any" || b == "any"
      a == b
    end

    def collections_for_slot(slot_name)
      (@artifact.collections || {}).select { |_name, coll| coll["slot"].to_s == slot_name }
    end

    def collection_slot?(slot_name)
      collections_for_slot(slot_name).any?
    end

    def add_error(type, slot: nil, collection: nil, detail: nil)
      @diags << LinkageDiagnostic.new(type: type, severity: :error,
                                       slot: slot, collection: collection, detail: detail)
    end

    def add_warning(type, slot: nil, collection: nil, detail: nil)
      @diags << LinkageDiagnostic.new(type: type, severity: :warning,
                                       slot: slot, collection: collection, detail: detail)
    end
  end
end
