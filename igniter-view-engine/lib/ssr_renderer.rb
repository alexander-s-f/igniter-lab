# frozen_string_literal: true

# igniter-lab/igniter-view-engine/lib/ssr_renderer.rb
#
# SSRRenderer — consumes a ViewArtifact + optional slot values and emits
# static HTML with hydration data-attributes baked in.
#
# Design contracts:
#   - No contract execution.
#   - No network IO of any kind.
#   - No framework dependency (plain Ruby, stdlib only).
#   - Evaluates display_rules server-side so initial render is correct
#     without JavaScript.
#   - Embeds only data-ig-* attributes needed for JS micro-runtime hydration.
#
# Status: experimental · lab-only · no-canon · no-public-api
# Track: lab-igniter-isomorphic-view-artifact-mvp-boundary-v0

require "json"
require "cgi"
require_relative "igniter_view_engine"
require_relative "view_artifact"

module IgniterView
  class SSRRenderer
    SELF_CLOSING_TAGS = %w[area base br col embed hr img input
                           link meta param source track wbr].freeze

    # artifact:    ViewArtifact instance
    # slot_values: { "has_warnings" => false } — injected by host, read-only
    def initialize(artifact, slot_values: {})
      @artifact    = artifact
      @ui_state    = artifact.initial_ui_state.dup
      @slot_values = slot_values.transform_keys(&:to_s)
    end

    # Override initial UIState (e.g. for SSR with server-determined active tab).
    def with_ui_state(overrides)
      known = @artifact.initial_ui_state.keys
      overrides.transform_keys(&:to_s).each do |k, v|
        @ui_state[k] = v if known.include?(k)
      end
      self
    end

    # Render the root container element with all hydration attributes embedded.
    # Yields a render context (self) so callers can compose child elements.
    #
    # Returns a complete HTML string.
    def render_root(tag: "div", extra_attrs: {}, &block)
      inner_html = block ? instance_exec(&block) : ""

      attrs = {
        "data-ig-component"       => @artifact.view_id,
        "data-ig-state"           => JSON.generate(@ui_state),
        "data-ig-slots"           => JSON.generate(@slot_values),
        "data-ig-artifact-digest" => @artifact.artifact_digest
      }.merge(extra_attrs.transform_keys(&:to_s))

      build_tag(tag, attrs, safe(inner_html))
    end

    # Render a named element from the artifact.
    # Evaluates display_rules with initial state server-side and inlines
    # resulting classes / aria attributes.
    #
    # element_id:   matches artifact element definition
    # node_params:  { "id" => "overview" } — per-instance render context
    # tag:          HTML tag to emit
    # content:      inner HTML / text content
    # extra_attrs:  additional static HTML attributes
    def render_element(element_id, node_params: {}, tag: "div",
                       content: nil, extra_attrs: {}, &block)
      elem_def = @artifact.element(element_id)
      raise ArgumentError, "SSRRenderer: unknown element '#{element_id}'" unless elem_def

      node_params_s = node_params.transform_keys(&:to_s)
      computed      = apply_display_rules(elem_def.display_rules, node_params_s)

      # Merge static + computed classes
      all_classes = [elem_def.static_classes, computed[:classes]]
                    .map(&:to_s).reject(&:empty?).join(" ").strip

      attrs = { "data-ig-element" => element_id.to_s }
      attrs["data-ig-param"] = JSON.generate(node_params_s) unless node_params_s.empty?
      attrs["class"]         = all_classes                  unless all_classes.empty?

      computed[:aria].each { |k, v| attrs["aria-#{k}"] = v.to_s }
      attrs.merge!(extra_attrs.transform_keys(&:to_s))

      inner = if block
                instance_exec(&block)
              elsif content.is_a?(SafeString)
                content.to_s
              elsif content
                CGI.escapeHTML(content.to_s)
              else
                ""
              end

      build_tag(tag, attrs, safe(inner))
    end

    # Helper: safe literal text inside render blocks
    def text(str)
      CGI.escapeHTML(str.to_s)
    end

    # Inline the artifact JSON as a <script type="application/json"> tag.
    # The JS micro-runtime reads this to bootstrap without a network fetch.
    def artifact_script_tag
      id = "ig-artifact-#{@artifact.view_id.gsub(/[^a-z0-9_\-]/i, "-")}"
      "<script type=\"application/json\" id=\"#{id}\">#{@artifact.to_json}</script>"
    end

    # Render a named collection as a container with repeated item elements.
    #
    # P5 — lab-only · no-stable-schema
    #
    # Protocol:
    #   - Reads item array from slot_values[collection_def["slot"]]
    #   - Renders a `<template data-ig-collection-template>` element (used by JS runtime
    #     to clone new items on slot update — no innerHTML required)
    #   - Renders one `data-ig-element` per item with params from the item hash
    #   - Display rules are evaluated server-side per item (same expression evaluator)
    #
    # collection_name:        key in artifact.collections
    # items:                  optional explicit array override (defaults to slot data)
    # extra_container_attrs:  additional HTML attributes for the container element
    #
    # Yields per-item block with item_params hash if a block is given.
    # Block return value is treated as inner HTML for the item (auto-escaped unless SafeString).
    def render_collection(collection_name, items: nil, extra_container_attrs: {}, &item_block)
      coll_def = @artifact.collection(collection_name)
      raise ArgumentError, "SSRRenderer: unknown collection '#{collection_name}'" unless coll_def

      slot_name  = coll_def["slot"]
      elem_name  = coll_def["item_element"]
      item_key   = coll_def["item_key"] || "id"
      cont_tag   = coll_def["container_tag"] || "ul"
      item_tag   = coll_def["item_tag"] || "li"
      cont_cls   = coll_def["container_classes"] || ""

      items ||= Array(@slot_values[slot_name] || [])

      container_attrs = {
        "data-ig-collection"         => collection_name.to_s,
        "data-ig-collection-slot"    => slot_name.to_s,
        "data-ig-collection-element" => elem_name.to_s,
        "data-ig-collection-key"     => item_key.to_s
      }
      container_attrs["class"] = cont_cls unless cont_cls.empty?
      container_attrs.merge!(extra_container_attrs.transform_keys(&:to_s))

      # Render the template element — bare item shell for JS runtime to clone.
      # Contains only the data-ig-element attr; JS sets data-ig-param before display rules.
      template_inner = "<#{item_tag} data-ig-element=\"#{CGI.escapeHTML(elem_name)}\"></#{item_tag}>"
      template_html  = "<template data-ig-collection-template=\"#{CGI.escapeHTML(collection_name.to_s)}\">" \
                       "#{template_inner}</template>"

      # Render each item from the slot array
      items_html = items.map.with_index do |item, _idx|
        item_s = item.is_a?(Hash) ? item.transform_keys(&:to_s) : {}
        key    = item_s[item_key.to_s]

        inner_content = item_block ? instance_exec(item_s, &item_block) : nil

        render_element(
          elem_name,
          node_params:  item_s,
          tag:          item_tag,
          content:      inner_content,
          extra_attrs:  { "data-ig-item-key" => key.to_s }
        )
      end.join

      build_tag(cont_tag, container_attrs, safe(template_html + items_html))
    end

    private

    # ── Pure expression evaluator (mirrors JS evaluator) ──────────────────────
    def evaluate_expr(expr, node_params)
      return expr unless expr.is_a?(Array)
      op, *args = expr
      case op
      when "ui_state" then @ui_state[args[0].to_s]
      when "slot"     then @slot_values[args[0].to_s]
      when "param"    then node_params[args[0].to_s]
      when "eq"       then evaluate_expr(args[0], node_params) == evaluate_expr(args[1], node_params)
      when "neq"      then evaluate_expr(args[0], node_params) != evaluate_expr(args[1], node_params)
      when "gt"       then num(evaluate_expr(args[0], node_params)) >  num(evaluate_expr(args[1], node_params))
      when "lt"       then num(evaluate_expr(args[0], node_params)) <  num(evaluate_expr(args[1], node_params))
      when "gte"      then num(evaluate_expr(args[0], node_params)) >= num(evaluate_expr(args[1], node_params))
      when "lte"      then num(evaluate_expr(args[0], node_params)) <= num(evaluate_expr(args[1], node_params))
      when "and"      then !!evaluate_expr(args[0], node_params) && !!evaluate_expr(args[1], node_params)
      when "or"       then !!evaluate_expr(args[0], node_params) || !!evaluate_expr(args[1], node_params)
      when "not"      then !evaluate_expr(args[0], node_params)
      else nil
      end
    end

    def num(v) = v.to_f

    def apply_display_rules(rules, node_params)
      result = { classes: +"", aria: {} }
      (rules || []).each do |rule|
        next unless rule.is_a?(Array)
        kind = rule[0].to_s
        case kind
        when "style"
          _, condition, true_eff, false_eff = rule
          effect = evaluate_expr(condition, node_params) ? true_eff : false_eff
          merge_effect!(result, effect)
        when "match"
          _, subject, cases, default_eff = rule
          val    = evaluate_expr(subject, node_params).to_s
          effect = (cases || {})[val] || default_eff
          merge_effect!(result, effect)
        end
      end
      result
    end

    def merge_effect!(result, effect)
      return unless effect.is_a?(Hash)
      c = effect["c"] || effect[:c]
      a = effect["a"] || effect[:a]
      result[:classes] = [result[:classes], c.to_s].reject(&:empty?).join(" ") if c
      result[:aria].merge!(a.transform_keys(&:to_s)) if a.is_a?(Hash)
    end

    # ── HTML building helpers ─────────────────────────────────────────────────
    def build_tag(tag, attrs, inner_safe)
      attrs_str = attrs.map { |k, v| " #{k}=\"#{CGI.escapeHTML(v.to_s)}\"" }.join
      if SELF_CLOSING_TAGS.include?(tag.to_s.downcase) && inner_safe.to_s.empty?
        "<#{tag}#{attrs_str}/>"
      else
        "<#{tag}#{attrs_str}>#{inner_safe}</#{tag}>"
      end
    end

    def safe(str) = SafeString.new(str.to_s)
  end
end
