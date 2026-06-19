# frozen_string_literal: true

# igniter-lab/igniter-view-engine/lib/linkage_report.rb
#
# LinkageReport — lab-only unified diagnostic report.
#
# Combines diagnostics from three static-analysis layers into a single
# developer-readable report with JSON output (CI-safe) and text output
# (terminal-friendly):
#
#   Layer :extractor — CompiledContractExtractor::ExtractionResult
#     (type normalization warnings: :missing_item_fields, :opaque_struct_type)
#
#   Layer :overlay   — ContractSchemaSupplement::OverlayResult
#     (merge validation: :contract_id_mismatch, :supplement_to_non_array,
#      :unknown_output_ref, :unrecognized_supplement_key)
#
#   Layer :linker    — SlotTypeLinker::LinkageResult
#     (slot-to-output linkage: :unresolved_contract_ref, :missing_output_ref,
#      :slot_type_mismatch, :missing_required_item_field, :non_array_collection_slot,
#      :missing_item_fields_schema, :item_field_type_mismatch, :extra_item_field)
#
# Usage:
#   report = LinkageReport.build(
#     contract_id:       "search",
#     view_id:           "igniter.lab.results_panel",
#     extraction_result: extracted,
#     overlay_result:    overlay,
#     linkage_result:    linkage
#   )
#   report.valid?          # → true/false
#   report.error_count     # → Integer
#   report.warning_count   # → Integer
#   puts report.to_text    # developer-readable
#   report.to_h            # JSON-safe Hash (no absolute paths)
#
# Pipeline convenience:
#   report = LinkageReport.build_pipeline(
#     igv_path:              "fixtures/results_panel.igv",
#     compiled_contract_path: "fixtures/compiled_contracts/search_compiled.json",
#     supplement_path:        "fixtures/schema_supplements/search_supplement.json"
#   )
#
# Does NOT:
#   - Execute contracts or require Igniter::Contract
#   - Persist absolute filesystem paths in report output
#   - Make network requests
#   - Mutate ViewArtifact, ContractSchema, or any existing result object
#
# Status: experimental · lab-only · no-canon · no-public-api · no-stable-schema
# Track: lab-igniter-view-linkage-diagnostic-report-proof-v0

require "json"
require_relative "compiled_contract_extractor"
require_relative "contract_schema_supplement"
require_relative "slot_type_linker"
require_relative "igv_compiler"

module IgniterView
  class LinkageReport
    # ── Report entry: one normalized diagnostic from any layer ───────────────

    ReportEntry = Struct.new(
      :source_layer,  # :extractor | :overlay | :linker
      :severity,      # :error | :warning
      :type,          # original type symbol
      :field,         # output/param name (extractor/overlay) or slot name (linker)
      :collection,    # collection name — linker only, nil otherwise
      :detail,
      keyword_init: true
    ) do
      def error?   = severity == :error
      def warning? = severity == :warning

      def to_h
        h = {
          "source_layer" => source_layer.to_s,
          "severity"     => severity.to_s,
          "type"         => type.to_s,
          "detail"       => detail
        }
        h["field"]      = field      if field
        h["collection"] = collection if collection
        h
      end
    end

    # ── Accessors ────────────────────────────────────────────────────────────

    attr_reader :contract_id, :view_id, :entries

    def initialize(contract_id:, view_id: nil, entries: [])
      @contract_id = contract_id.to_s
      @view_id     = view_id&.to_s
      @entries     = Array(entries).freeze
    end

    # ── Status ───────────────────────────────────────────────────────────────

    def valid?
      @entries.none?(&:error?)
    end

    def error_count
      @entries.count(&:error?)
    end

    def warning_count
      @entries.count(&:warning?)
    end

    def entry_count
      @entries.size
    end

    def errors
      @entries.select(&:error?)
    end

    def warnings
      @entries.select(&:warning?)
    end

    def entries_for(layer:)
      @entries.select { |e| e.source_layer == layer.to_sym }
    end

    # ── Class-level builders ─────────────────────────────────────────────────

    # Build from pre-computed result objects.
    #
    # @param contract_id       [String]
    # @param view_id           [String, nil]
    # @param extraction_result [CompiledContractExtractor::ExtractionResult, nil]
    # @param overlay_result    [ContractSchemaSupplement::OverlayResult, nil]
    # @param linkage_result    [LinkageResult, nil]
    # @return [LinkageReport]
    def self.build(contract_id:, view_id: nil,
                   extraction_result: nil,
                   overlay_result:    nil,
                   linkage_result:    nil)
      entries = []

      # Extraction layer
      if extraction_result
        extraction_result.diagnostics.each do |d|
          entries << ReportEntry.new(
            source_layer: :extractor,
            severity:     d.severity,
            type:         d.type,
            field:        d.field,
            collection:   nil,
            detail:       d.detail
          )
        end
      end

      # Overlay layer
      if overlay_result
        overlay_result.diagnostics.each do |d|
          entries << ReportEntry.new(
            source_layer: :overlay,
            severity:     d.severity,
            type:         d.type,
            field:        d.field,
            collection:   nil,
            detail:       d.detail
          )
        end
      end

      # Linker layer
      if linkage_result
        linkage_result.diagnostics.each do |d|
          entries << ReportEntry.new(
            source_layer: :linker,
            severity:     d.severity,
            type:         d.type,
            field:        d.slot,
            collection:   d.collection,
            detail:       d.detail
          )
        end
      end

      new(contract_id: contract_id, view_id: view_id, entries: entries)
    end

    # Pipeline convenience: run the full extraction → supplement → linkage
    # pipeline from file paths and return a LinkageReport.
    #
    # @param igv_path              [String] path to .igv view file
    # @param compiled_contract_path [String] path to compiled contract JSON
    # @param supplement_path       [String, nil] path to supplement JSON (optional)
    # @return [LinkageReport]
    def self.build_pipeline(igv_path:, compiled_contract_path:, supplement_path: nil)
      # 1. Compile the view
      compile_result = IgvCompiler.compile_file(igv_path)
      unless compile_result.success?
        raise ArgumentError,
              "LinkageReport.build_pipeline: .igv compile failed: #{compile_result.errors.inspect}"
      end
      artifact = compile_result.artifact
      view_id  = artifact.view_id

      # 2. Extract compiled contract schema
      extraction_result = CompiledContractExtractor.extract(compiled_contract_path)
      unless extraction_result.valid?
        # Return early with extractor errors only
        return build(
          contract_id:       extraction_result.schema&.contract_id || File.basename(compiled_contract_path, ".json"),
          view_id:           view_id,
          extraction_result: extraction_result,
          overlay_result:    nil,
          linkage_result:    nil
        )
      end

      extracted_schema = extraction_result.schema
      contract_id      = extracted_schema.contract_id

      # 3. Apply supplement (optional)
      overlay_result = nil
      final_schema   = extracted_schema

      if supplement_path && File.exist?(supplement_path)
        supplement = ContractSchemaSupplement.load_file(supplement_path)
        overlay_result = supplement.apply_to(extracted_schema)
        final_schema   = overlay_result.valid? ? overlay_result.schema : extracted_schema
      end

      # 4. Link
      schemas       = { contract_id => final_schema }
      linkage_result = SlotTypeLinker.link(artifact, schemas)

      build(
        contract_id:       contract_id,
        view_id:           view_id,
        extraction_result: extraction_result,
        overlay_result:    overlay_result,
        linkage_result:    linkage_result
      )
    end

    # ── JSON report ───────────────────────────────────────────────────────────

    # Returns a JSON-safe Hash with no absolute filesystem paths.
    def to_h
      by_layer = [:extractor, :overlay, :linker].each_with_object({}) do |layer, h|
        layer_entries = entries_for(layer: layer)
        h[layer.to_s] = {
          "errors"   => layer_entries.count(&:error?),
          "warnings" => layer_entries.count(&:warning?),
          "total"    => layer_entries.size
        }
      end

      {
        "_status"     => NON_CLAIMS,
        "view_id"     => @view_id,
        "contract_id" => @contract_id,
        "valid"       => valid?,
        "summary"     => {
          "errors"        => error_count,
          "warnings"      => warning_count,
          "total_entries" => entry_count,
          "by_layer"      => by_layer
        },
        "entries"     => @entries.map(&:to_h)
      }.compact
    end

    # ── Text renderer ─────────────────────────────────────────────────────────

    # Returns a compact developer-readable text report.
    # Stable output (deterministic order: extractor → overlay → linker).
    def to_text
      lines = []
      bar   = "─" * 58

      # Header
      lines << ("═" * 58)
      lines << "LINKAGE REPORT"
      lines << "  view:     #{@view_id || "(no view_id)"}"
      lines << "  contract: #{@contract_id}"
      status_icon = valid? ? "✅ VALID" : "❌ INVALID"
      count_str   = "#{error_count} error#{error_count == 1 ? "" : "s"} · " \
                    "#{warning_count} warning#{warning_count == 1 ? "" : "s"}"
      lines << "  status:   #{status_icon}  (#{count_str})"
      lines << bar

      # Per-layer sections
      [:extractor, :overlay, :linker].each do |layer|
        layer_entries = entries_for(layer: layer)
        layer_label   = "[#{layer}]".ljust(12)

        if layer_entries.empty?
          lines << "  #{layer_label}  — no diagnostics"
        else
          layer_entries.each_with_index do |e, i|
            sev_icon = e.error? ? "E" : "W"
            context  = [e.field, e.collection ? "coll=#{e.collection}" : nil].compact.join(", ")
            context_str = context.empty? ? "" : " [#{context}]"
            prefix  = i.zero? ? "  #{layer_label}" : "  #{" " * 12}"
            lines << "#{prefix}  [#{sev_icon}] :#{e.type}#{context_str}"
            # Wrap detail to 56 chars, indented
            detail_lines = wrap_text(e.detail.to_s, 52)
            detail_lines.each do |dl|
              lines << "  #{" " * 14}    #{dl}"
            end
          end
        end
      end

      lines << bar
      lines << ("═" * 58)
      lines.join("\n")
    end

    private

    NON_CLAIMS = "experimental · lab-only · no-canon · no-public-api · no-stable-schema"

    def wrap_text(text, width)
      return [""] if text.empty?
      words  = text.split
      result = []
      current = +""
      words.each do |word|
        if current.empty?
          current = word
        elsif (current.length + 1 + word.length) <= width
          current << " " << word
        else
          result << current
          current = word
        end
      end
      result << current unless current.empty?
      result
    end
  end
end
