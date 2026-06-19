# frozen_string_literal: true

# igniter-lab/igniter-view-engine/lib/compiled_contract_extractor.rb
#
# CompiledContractExtractor — lab-only static extractor.
#
# Reads a compiled contract artifact JSON (the format emitted by the Igniter
# compiler into <igapp>/contracts/<name>.json) and produces a ContractSchema
# suitable for use with SlotTypeLinker.
#
# Source format (output_ports is the authoritative source):
#   {
#     "contract_id": "Search",
#     "output_ports": [
#       { "name": "results", "type_tag": "Collection[SearchResult]", "required": true },
#       { "name": "query",   "type_tag": "String",  "required": true },
#       { "name": "total",   "type_tag": "Integer", "required": true }
#     ],
#     ...
#   }
#
# Type tag normalization:
#   "Integer"           → "integer"
#   "String"            → "string"
#   "Float"             → "float"
#   "Boolean" / "Bool"  → "boolean"
#   "Collection[X]"     → "array"   (item_fields NOT in compiled output → :missing_item_fields warning)
#   "Array[X]"          → "array"
#   "List[X]"           → "array"
#   "Decimal[N]"        → "float"
#   "Object"            → "object"
#   "Any"               → "any"
#   Unknown struct name → "object"  + :opaque_struct_type warning
#
# Diagnostic severity:
#   ERROR:   :malformed_artifact      — not valid JSON / missing root keys
#            :missing_contract_id     — "contract_id" key absent or empty
#            :missing_output_ports    — "output_ports" key absent
#            :invalid_output_entry    — output port missing "name" field
#   WARNING: :missing_item_fields     — Collection/Array/List type; item_fields not in compiled format
#            :opaque_struct_type      — custom struct type mapped to "object"
#            :empty_output_ports      — contract has no output ports (unusual)
#
# Does NOT:
#   - Execute contracts
#   - Load, require, or depend on Igniter::Contract at runtime
#   - Mutate ViewArtifact or its digest
#   - Make network requests
#
# Status: experimental · lab-only · no-canon · no-public-api · no-stable-schema
# Track: lab-igniter-view-contract-schema-extraction-proof-v0

require "json"
require_relative "contract_schema"

module IgniterView
  class CompiledContractExtractor
    # ── Diagnostic types ────────────────────────────────────────────────────

    ExtractionDiagnostic = Struct.new(:type, :severity, :field, :detail, keyword_init: true) do
      def error?   = severity == :error
      def warning? = severity == :warning

      def to_h
        { type: type.to_s, severity: severity.to_s, field: field, detail: detail }.compact
      end
    end

    # ── Extraction result ────────────────────────────────────────────────────

    class ExtractionResult
      attr_reader :schema, :diagnostics, :source

      def initialize(schema:, diagnostics:, source: nil)
        @schema      = schema
        @diagnostics = Array(diagnostics).freeze
        @source      = source
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
          "source"      => @source,
          "diagnostics" => @diagnostics.map(&:to_h)
        }.compact
      end
    end

    # ── Type tag normalization table ─────────────────────────────────────────

    SCALAR_TYPE_MAP = {
      "integer" => "integer",
      "int"     => "integer",
      "string"  => "string",
      "str"     => "string",
      "float"   => "float",
      "double"  => "float",
      "number"  => "float",
      "boolean" => "boolean",
      "bool"    => "boolean",
      "object"  => "object",
      "map"     => "object",
      "hash"    => "object",
      "array"   => "array",
      "any"     => "any",
      "unknown" => "any"
    }.freeze

    COLLECTION_PREFIXES = %w[collection array list].freeze

    # ── Class-level API ──────────────────────────────────────────────────────

    # Extract a ContractSchema from a compiled contract JSON file.
    #
    # @param path [String, Pathname] path to the contract JSON file
    # @return [ExtractionResult]
    def self.extract(path)
      source = path.to_s
      raw = File.read(source, encoding: "utf-8")
      data = JSON.parse(raw)
      new(data, source: source).extract
    rescue Errno::ENOENT
      error_result("file not found: '#{path}'", source: path.to_s)
    rescue JSON::ParserError => e
      error_result("malformed JSON in '#{path}': #{e.message}", source: path.to_s)
    end

    # Extract from a pre-parsed Hash (for testing / pipeline use).
    #
    # @param data [Hash] parsed JSON data
    # @param source [String, nil] optional source label for diagnostics
    # @return [ExtractionResult]
    def self.extract_data(data, source: nil)
      new(data, source: source).extract
    rescue => e
      error_result(e.message, source: source)
    end

    # Extract all contract JSONs from a directory.
    # Returns a Hash { contract_id => ContractSchema } — only valid extractions included.
    # Logs warnings to stderr for failed extractions.
    #
    # @param dir_path [String] directory containing contract JSON files
    # @return [Hash { String => ContractSchema }]
    def self.extract_dir(dir_path)
      schemas = {}
      Dir.glob(File.join(dir_path.to_s, "*.json")).sort.each do |path|
        result = extract(path)
        if result.valid? && result.schema
          schemas[result.schema.contract_id] = result.schema
        else
          result.errors.each do |d|
            warn "[CompiledContractExtractor] Skipping #{File.basename(path)}: #{d.detail}"
          end
        end
      end
      schemas
    end

    # ── Instance ────────────────────────────────────────────────────────────

    def initialize(data, source: nil)
      @data   = data
      @source = source
      @diags  = []
    end

    def extract
      unless @data.is_a?(Hash)
        add_error(:malformed_artifact, detail: "Root must be a JSON object, got #{@data.class}")
        return build_result(nil)
      end

      contract_id = @data["contract_id"].to_s.strip
      if contract_id.empty?
        add_error(:missing_contract_id,
                  detail: "Compiled contract has no 'contract_id' field. " \
                          "Cannot extract ContractSchema.")
        return build_result(nil)
      end

      output_ports = @data["output_ports"]
      if output_ports.nil?
        add_error(:missing_output_ports,
                  detail: "Contract '#{contract_id}' has no 'output_ports' field. " \
                          "Cannot extract output schema.")
        return build_result(nil)
      end

      unless output_ports.is_a?(Array)
        add_error(:missing_output_ports,
                  detail: "Contract '#{contract_id}': 'output_ports' must be an Array, " \
                          "got #{output_ports.class}.")
        return build_result(nil)
      end

      if output_ports.empty?
        add_warning(:empty_output_ports,
                    detail: "Contract '#{contract_id}' has empty output_ports. " \
                            "Extracted ContractSchema will have no outputs.")
      end

      outputs = build_outputs(contract_id, output_ports)
      schema  = ContractSchema.build(contract_id, outputs)
      build_result(schema)
    end

    private

    # ── Output port processing ───────────────────────────────────────────────

    def build_outputs(contract_id, output_ports)
      outputs = {}
      output_ports.each do |port|
        next unless port.is_a?(Hash)

        name = port["name"].to_s.strip
        if name.empty?
          add_error(:invalid_output_entry,
                    detail: "Contract '#{contract_id}' has an output port with no 'name'. Skipping.")
          next
        end

        type_tag = port["type_tag"].to_s
        normalized, extra_diags = normalize_type_tag(type_tag, name)
        extra_diags.each { |d| @diags << d }

        outputs[name] = { "type" => normalized }
      end
      outputs
    end

    # ── Type tag normalization ────────────────────────────────────────────────

    def normalize_type_tag(type_tag, field_name = nil)
      diags = []
      return ["any", diags] if type_tag.nil? || type_tag.strip.empty?

      lower = type_tag.strip.downcase

      # Direct scalar map (case-insensitive)
      if SCALAR_TYPE_MAP.key?(lower)
        return [SCALAR_TYPE_MAP[lower], diags]
      end

      # Parameterized collection: Collection[X], Array[X], List[X]
      COLLECTION_PREFIXES.each do |prefix|
        if lower.start_with?("#{prefix}[")
          diags << ExtractionDiagnostic.new(
            type:     :missing_item_fields,
            severity: :warning,
            field:    field_name,
            detail:   "Output '#{field_name}' has type '#{type_tag}' — mapped to 'array'. " \
                      "Compiled contract format does not carry item_fields. " \
                      "SlotTypeLinker will emit :missing_item_fields_schema for collection slots " \
                      "linked to this output. Add item_fields manually to a hand-authored fixture " \
                      "if field-level validation is required."
          )
          return ["array", diags]
        end
      end

      # Decimal[N] — fixed-precision numeric → float
      if lower.match?(/\Adecimal\[/)
        return ["float", diags]
      end

      # Opaque struct / custom named type → object + warning
      diags << ExtractionDiagnostic.new(
        type:     :opaque_struct_type,
        severity: :warning,
        field:    field_name,
        detail:   "Output '#{field_name}' has opaque type '#{type_tag}' — " \
                  "no direct ContractSchema mapping. Mapped to 'object'. " \
                  "SlotTypeLinker will accept slot type='object' as compatible. " \
                  "Verify this mapping is correct for your use case."
      )
      ["object", diags]
    end

    # ── Helpers ──────────────────────────────────────────────────────────────

    def add_error(type, field: nil, detail: nil)
      @diags << ExtractionDiagnostic.new(type: type, severity: :error, field: field, detail: detail)
    end

    def add_warning(type, field: nil, detail: nil)
      @diags << ExtractionDiagnostic.new(type: type, severity: :warning, field: field, detail: detail)
    end

    def build_result(schema)
      ExtractionResult.new(schema: schema, diagnostics: @diags.dup, source: @source)
    end

    def self.error_result(message, source: nil)
      diag = ExtractionDiagnostic.new(
        type:     :malformed_artifact,
        severity: :error,
        detail:   message
      )
      ExtractionResult.new(schema: nil, diagnostics: [diag], source: source)
    end
    private_class_method :error_result
  end
end
