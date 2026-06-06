# frozen_string_literal: true

# igniter-lab/igniter-view-engine/lib/contract_schema.rb
#
# ContractSchema — minimal lab-only representation of an Igniter contract's
# output type schema, used for static slot-contract type linkage validation.
#
# Does NOT execute, require, or depend on any Igniter::Contract at runtime.
# This is a structural description only — a simplified type envelope.
#
# JSON format (fixtures/contract_schemas/*.json):
#   {
#     "contract_id": "search",
#     "outputs": {
#       "results": {
#         "type": "array",
#         "item_fields": {
#           "id":    { "type": "string",  "required": true },
#           "score": { "type": "integer", "required": false }
#         }
#       },
#       "query": { "type": "string" }
#     }
#   }
#
# Slot `from:` resolution:
#   "search.results" → contract_id="search", output_name="results"
#   First dot is the separator. Everything before first dot = contract_id.
#
# Status: experimental · lab-only · no-canon · no-public-api · no-stable-schema
# Track: lab-igniter-view-slot-contract-type-linkage-proof-v0

require "json"

module IgniterView
  class ContractSchema
    KNOWN_TYPES = %w[string integer float boolean array object any].freeze

    attr_reader :contract_id, :outputs

    def initialize(contract_id:, outputs: {})
      @contract_id = contract_id.to_s
      @outputs     = normalize_outputs(outputs)
    end

    # Look up a single output definition by name.
    # Returns the output Hash or nil.
    def output(name)
      @outputs[name.to_s]
    end

    # Load a single ContractSchema from a JSON file.
    # Falls back to using the filename (sans .json) as contract_id if not in JSON.
    def self.load_file(path)
      data = JSON.parse(File.read(path.to_s, encoding: "utf-8"))
      new(
        contract_id: data["contract_id"] || File.basename(path.to_s, ".json"),
        outputs:     data["outputs"] || {}
      )
    rescue JSON::ParserError => e
      raise ArgumentError,
            "ContractSchema.load_file: malformed JSON in '#{path}': #{e.message}"
    rescue Errno::ENOENT
      raise ArgumentError,
            "ContractSchema.load_file: file not found: '#{path}'"
    end

    # Load all *.json files in a directory.
    # Returns Hash { contract_id (String) => ContractSchema }.
    # Skips files that fail to parse (with a warning to stderr).
    def self.load_dir(dir_path)
      schemas = {}
      Dir.glob(File.join(dir_path.to_s, "*.json")).sort.each do |path|
        schema = load_file(path)
        schemas[schema.contract_id] = schema
      rescue ArgumentError => e
        warn "[ContractSchema] Skipping #{path}: #{e.message}"
      end
      schemas
    end

    # Build programmatically (for tests / proof runner).
    def self.build(contract_id, outputs)
      new(contract_id: contract_id, outputs: outputs)
    end

    def to_h
      { "contract_id" => @contract_id, "outputs" => @outputs }
    end

    private

    def normalize_outputs(outputs)
      (outputs || {}).transform_keys(&:to_s).transform_values do |v|
        next v unless v.is_a?(Hash)
        out = v.transform_keys(&:to_s)
        if out["item_fields"].is_a?(Hash)
          out["item_fields"] = out["item_fields"].transform_keys(&:to_s).transform_values do |f|
            f.is_a?(Hash) ? f.transform_keys(&:to_s) : f
          end
        end
        out
      end
    end
  end
end
