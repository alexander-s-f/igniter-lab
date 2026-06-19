# igniter-lab/igniter-gui-engine/lib/hit_tester.rb
# frozen_string_literal: true

# Status: experimental · lab-only · no-canon · no-stable-schema · no-performance-claim

require_relative "scene_tree"

module IgniterGui
  class HitTester
    EVENT_MAP = {
      "click" => "on_click",
      "mousedown" => "on_mousedown",
      "mouseup" => "on_mouseup",
      "mousemove" => "on_mousemove"
    }.freeze

    def self.test(layout_result, scene_tree, x, y, event_kind = "click")
      # 1. Stale digest validation
      layout_digest = layout_result["scene_digest"] || layout_result[:scene_digest]
      if layout_digest != scene_tree.digest
        raise ValidationError.new("Stale scene digest: layout=#{layout_digest}, scene=#{scene_tree.digest}", check_id: "NGUI-P2-8")
      end

      # 2. Event kind validation
      unless EVENT_MAP.key?(event_kind)
        raise ValidationError.new("Unsupported event kind '#{event_kind}'", check_id: "NGUI-P2-7")
      end
      intent_key = EVENT_MAP[event_kind]

      # 3. Find candidates containing coordinates
      nodes_by_id = {}
      scene_tree.nodes.each_with_index { |n, idx| nodes_by_id[n["id"]] = { node: n, index: idx } }

      candidates = []
      resolved_nodes = layout_result["resolved_nodes"] || layout_result[:resolved_nodes]
      resolved_nodes.each do |res_node|
        id = res_node["id"] || res_node[:id]
        
        # Validation: unknown node id in layout result
        unless nodes_by_id.key?(id)
          raise ValidationError.new("Unknown node ID '#{id}' present in layout result", check_id: "NGUI-P2-6")
        end

        bounds = res_node["computed_bounds"] || res_node[:computed_bounds]
        next if bounds.nil?

        cx = bounds["x"] || bounds[:x]
        cy = bounds["y"] || bounds[:y]
        cw = bounds["w"] || bounds[:w]
        ch = bounds["h"] || bounds[:h]

        # Coordinate overlap check
        if x >= cx && x <= cx + cw && y >= cy && y <= cy + ch
          candidates << {
            id: id,
            bounds: bounds,
            node: nodes_by_id[id][:node],
            index: nodes_by_id[id][:index]
          }
        end
      end

      # 4. Return no-hit if empty
      if candidates.empty?
        return {
          "hit" => false,
          "target" => nil,
          "non_claims" => scene_tree.non_claims
        }
      end

      # 5. Overlap resolution: Sort by z_index descending (default 0), then declaration index descending
      candidates.sort_by! do |c|
        z = c[:node]["z_index"] || 0
        [-z, -c[:index]]
      end

      target = candidates.first
      matched_node = target[:node]

      # 6. Extract intent if present
      matched_intent = nil
      if matched_node["interaction_intents"].is_a?(Hash)
        matched_intent = matched_node["interaction_intents"][intent_key]
      end

      {
        "hit" => true,
        "target" => {
          "node_id" => target[:id],
          "computed_bounds" => target[:bounds],
          "matched_intent" => matched_intent
        },
        "non_claims" => scene_tree.non_claims
      }
    end
  end
end
