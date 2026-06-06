# frozen_string_literal: true

# igniter-lab/igniter-view-engine/lib/view_artifact.rb
#
# ViewArtifact — the isomorphic compiled definition for a view component.
# Consumed by both the Ruby SSR renderer and the vanilla JS micro-runtime.
# Content-addressed: digest changes when definition changes.
#
# Status: experimental · lab-only · no-canon · no-public-api · no-stable-syntax
# Track: lab-igniter-isomorphic-view-artifact-mvp-boundary-v0
#
# P5 schema extension (lab-only · no-stable-schema):
#   collections: {
#     "name" => {
#       "slot"              => "slot_name",    # declared slot providing the items array
#       "item_element"      => "element_name", # element_def used as repeated template
#       "item_key"          => "id",           # field name used as stable per-item key
#       "container_classes" => "...",          # static CSS for the container wrapper
#       "container_tag"     => "ul",           # HTML tag for the container
#       "item_tag"          => "li"            # HTML tag for each repeated item
#     }
#   }
#   Digest backward compatibility: collections excluded from digest when empty,
#   so P1/P2/P3 artifact digests remain unchanged.

require "json"
require "digest"

module IgniterView
  # ElementDef — one named element inside a ViewArtifact.
  # element_id:         unique name within the artifact
  # static_classes:     CSS classes always applied (SSR + client)
  # node_params_schema: { "id" => "string", ... } — declared param types
  # display_rules:      array of rule arrays (style / match)
  # interaction_rules:  array of event rule arrays (on)
  ElementDef = Struct.new(
    :element_id, :static_classes, :node_params_schema,
    :display_rules, :interaction_rules,
    keyword_init: true
  ) do
    def to_h
      {
        "element_id"         => element_id.to_s,
        "static_classes"     => static_classes.to_s,
        "node_params_schema" => (node_params_schema || {}).transform_keys(&:to_s),
        "display_rules"      => display_rules || [],
        "interaction_rules"  => interaction_rules || []
      }
    end
  end

  # ViewArtifact — the single source of truth for a view component.
  class ViewArtifact
    BANNED_OPCODES  = %w[fetch dispatch boot watch persistence eval innerHTML].freeze
    ALLOWED_OPCODES = %w[set_ui_state toggle_ui_state clear_ui_state].freeze

    attr_reader :view_id, :ui_states, :slots, :elements, :collections,
                :safety_policy, :non_claims, :artifact_digest

    # ui_states:   { "active_tab" => { "type" => "string", "default" => "overview" } }
    # slots:       { "has_warnings" => { "type" => "boolean", "contract_ref" => "...", "mode" => "read_only" } }
    # elements:    Array of ElementDef or raw hashes
    # collections: { "name" => { "slot" => "...", "item_element" => "...", ... } }  (P5, lab-only)
    def initialize(view_id:, ui_states: {}, slots: {}, elements: [], collections: {}, non_claims: [])
      @view_id     = view_id.to_s
      @ui_states   = normalize_keys(ui_states)
      @slots       = normalize_keys(slots)
      @elements    = elements.map { |e| e.is_a?(ElementDef) ? e : coerce_element(e) }
      @collections = normalize_collections(collections)
      @non_claims  = Array(non_claims)
      @safety_policy = {
        "banned_opcodes"             => BANNED_OPCODES,
        "allowed_opcodes"            => ALLOWED_OPCODES,
        "slot_mode"                  => "read_only",
        "interaction_target_domain"  => "ui_state_only",
        "dom_patch_scope"            => "class|aria|data only"
      }
      validate!
      @artifact_digest = compute_digest
    end

    # Serialise to plain Ruby Hash (JSON-safe).
    # collections key always present (may be {}) — host can detect collection-capable artifacts.
    def to_h
      {
        "view_id"         => @view_id,
        "artifact_digest" => @artifact_digest,
        "ui_states"       => @ui_states,
        "slots"           => @slots,
        "collections"     => @collections,
        "elements"        => @elements.map(&:to_h),
        "safety_policy"   => @safety_policy,
        "non_claims"      => @non_claims
      }
    end

    def to_json
      JSON.pretty_generate(to_h)
    end

    # Look up element definition by id.
    def element(element_id)
      @elements.find { |e| e.element_id.to_s == element_id.to_s }
    end

    # Look up collection definition by name.
    def collection(collection_name)
      @collections[collection_name.to_s]
    end

    # Initial UIState map: { "active_tab" => "overview" }
    def initial_ui_state
      @ui_states.transform_values { |cfg| cfg["default"] }
    end

    private

    def normalize_keys(hash)
      (hash || {}).transform_keys(&:to_s).transform_values do |v|
        v.is_a?(Hash) ? v.transform_keys(&:to_s) : v
      end
    end

    # Normalize collection definitions: string keys, nested string keys.
    def normalize_collections(collections)
      (collections || {}).transform_keys(&:to_s).transform_values do |coll_def|
        next {} unless coll_def.is_a?(Hash)
        coll_def.transform_keys(&:to_s)
      end
    end

    def coerce_element(h)
      h = h.transform_keys(&:to_s)
      ElementDef.new(
        element_id:         h["element_id"],
        static_classes:     h["static_classes"] || "",
        node_params_schema: h["node_params_schema"] || {},
        display_rules:      h["display_rules"] || [],
        interaction_rules:  h["interaction_rules"] || []
      )
    end

    def compute_digest
      # P5: collections excluded from digest when empty to preserve P1/P2/P3 backward compat.
      # A view with collections always has a different digest from one without.
      canonical_data = {
        "view_id"   => @view_id,
        "ui_states" => @ui_states.sort.to_h,
        "slots"     => @slots.sort.to_h,
        "elements"  => @elements.map { |e| e.to_h.sort.to_h }
      }
      canonical_data["collections"] = @collections.sort.to_h unless @collections.empty?
      canonical = JSON.generate(canonical_data)
      "sha256:#{Digest::SHA256.hexdigest(canonical)}"
    end

    def validate!
      # UIState and slot names must not overlap (D1 from LAB-TAILMIX-P1-A)
      overlap = @ui_states.keys & @slots.keys
      raise ArgumentError, "ViewArtifact '#{@view_id}': ui_states and slots share keys: #{overlap.inspect}" if overlap.any?

      slot_names    = @slots.keys
      element_ids   = @elements.map { |e| e.element_id.to_s }

      @elements.each do |elem|
        (elem.interaction_rules || []).each do |rule|
          next unless rule[0].to_s == "on"
          instructions = rule[2] || []
          instructions.each do |inst|
            op     = inst[0].to_s
            target = inst[1].to_s

            if BANNED_OPCODES.include?(op)
              raise ArgumentError,
                    "ViewArtifact '#{@view_id}' element '#{elem.element_id}': " \
                    "banned opcode '#{op}' rejected at build time"
            end

            unless ALLOWED_OPCODES.include?(op)
              raise ArgumentError,
                    "ViewArtifact '#{@view_id}' element '#{elem.element_id}': " \
                    "unknown opcode '#{op}' — only #{ALLOWED_OPCODES.join(", ")} are whitelisted"
            end

            # Slot mutation guard (IVF-P1-6)
            if slot_names.include?(target)
              raise ArgumentError,
                    "ViewArtifact '#{@view_id}' element '#{elem.element_id}': " \
                    "attempted mutation of read-only slot '#{target}'"
            end
          end
        end
      end

      # P5: Validate collection declarations
      validate_collections!(slot_names, element_ids)
    end

    # Validate collection references at build time.
    # Ensures slot and item_element exist; item_key is non-empty.
    def validate_collections!(slot_names, element_ids)
      @collections.each do |coll_name, coll_def|
        slot_ref = coll_def["slot"].to_s
        if slot_ref.empty?
          raise ArgumentError,
                "ViewArtifact '#{@view_id}' collection '#{coll_name}': `slot` is required"
        end
        unless slot_names.include?(slot_ref)
          raise ArgumentError,
                "ViewArtifact '#{@view_id}' collection '#{coll_name}': " \
                "slot '#{slot_ref}' not declared in slots"
        end

        elem_ref = coll_def["item_element"].to_s
        if elem_ref.empty?
          raise ArgumentError,
                "ViewArtifact '#{@view_id}' collection '#{coll_name}': `item_element` is required"
        end
        unless element_ids.include?(elem_ref)
          raise ArgumentError,
                "ViewArtifact '#{@view_id}' collection '#{coll_name}': " \
                "item_element '#{elem_ref}' not found in declared elements"
        end

        key_ref = coll_def["item_key"].to_s
        if key_ref.empty?
          raise ArgumentError,
                "ViewArtifact '#{@view_id}' collection '#{coll_name}': `item_key` must be non-empty"
        end
      end
    end
  end
end
