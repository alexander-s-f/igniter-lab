# igniter-lab/igniter-gui-engine/lib/event_dispatcher.rb
# frozen_string_literal: true

# Status: experimental · lab-only · no-canon · no-stable-schema · no-performance-claim

require "json"
require "time"
require "securerandom"
require_relative "scene_tree"
require_relative "slot_binder"

module IgniterGui
  class EventDispatcher
    POINTER_EVENTS = %w[click mousedown mouseup mousemove].freeze
    KEYBOARD_EVENTS = %w[keypress keydown keyup].freeze
    SUPPORTED_EVENTS = (POINTER_EVENTS + KEYBOARD_EVENTS).freeze

    EVENT_TO_INTENT_KEY = {
      "click" => "on_click",
      "mousedown" => "on_mousedown",
      "mouseup" => "on_mouseup",
      "mousemove" => "on_mousemove",
      "keypress" => "on_keypress",
      "keydown" => "on_keydown",
      "keyup" => "on_keyup"
    }.freeze

    ALLOWED_INTENTS = %w[select_tab toggle_sidebar submit_form close_modal].freeze

    def self.dispatch(layout_result, scene_tree, slot_values, event)
      # 1. Bounded event payload size check (NGUI-P9-12)
      begin
        serialized = JSON.generate(event)
        if serialized.bytesize > 2000
          raise ValidationError.new("Oversized event payload (#{serialized.bytesize} > 2000 bytes)", check_id: "NGUI-P9-12")
        end
      rescue => e
        raise ValidationError.new("Event payload is not serializable: #{e.message}", check_id: "NGUI-P9-12")
      end

      # 2. Stale scene digest guard (NGUI-P9-8)
      layout_digest = layout_result["scene_digest"] || layout_result[:scene_digest]
      if layout_digest != scene_tree.digest
        raise ValidationError.new("Stale scene digest: layout=#{layout_digest}, scene=#{scene_tree.digest}", check_id: "NGUI-P9-8")
      end

      # 3. Undeclared slot/capability params check (NGUI-P9-10)
      slot_values.each_key do |key|
        next if key.to_s == "non_claims"
        unless scene_tree.slots.key?(key.to_s)
          raise ValidationError.new("SlotValues contains undeclared slot key '#{key}'", check_id: "NGUI-P9-10")
        end
      end

      # 4. Supported event validation (NGUI-P9-6)
      event_type = (event["type"] || event[:type] || event["event_kind"] || event[:event_kind]).to_s
      unless SUPPORTED_EVENTS.include?(event_type)
        raise ValidationError.new("Unsupported event kind '#{event_type}'", check_id: "NGUI-P9-6")
      end

      # 4.5. Validate all resolved layout boxes exist (NGUI-P9-9)
      resolved_nodes = layout_result["resolved_nodes"] || layout_result[:resolved_nodes] || []
      resolved_nodes.each do |res_node|
        bounds = res_node["computed_bounds"] || res_node[:computed_bounds]
        if bounds.nil?
          id = res_node["id"] || res_node[:id]
          raise ValidationError.new("Node '#{id}' is missing resolved layout bounds", check_id: "NGUI-P9-9")
        end
      end

      # 5. Bind scene to resolve visibility, active state, and styles
      bind_res = SlotBinder.bind(layout_result, scene_tree, slot_values, strict_binding: true)
      bound_scene = bind_res[:bound_scene]

      # Map bound nodes by ID for quick access
      bound_nodes_map = {}
      bound_scene["bound_nodes"].each { |n| bound_nodes_map[n["id"]] = n }

      # Route event
      if POINTER_EVENTS.include?(event_type)
        # Extract coordinates
        x = event["x"] || event[:x]
        y = event["y"] || event[:y]

        if x.nil? || y.nil? || !x.is_a?(Numeric) || !y.is_a?(Numeric)
          raise ValidationError.new("Pointer event is missing numeric x/y coordinates", check_id: "NGUI-P9-6")
        end

        # Find candidates containing coordinates
        candidates = []
        bound_scene["bound_nodes"].each_with_index do |b_node, index|
          id = b_node["id"]
          style = b_node["style"] || {}

          cx = style["x"]
          cy = style["y"]
          cw = style["width"] || style["w"]
          ch = style["height"] || style["h"]

          # NGUI-P9-9: unresolved layout box fails closed
          if cx.nil? || cy.nil? || cw.nil? || ch.nil?
            raise ValidationError.new("Node '#{id}' is missing resolved layout bounds", check_id: "NGUI-P9-9")
          end

          # NGUI-P9-4: Hidden or inactive nodes do not dispatch intents
          next if b_node["visible"] == false || b_node["active"] == false

          if x >= cx && x <= cx + cw && y >= cy && y <= cy + ch
            # Find original node for z-index
            orig_node = scene_tree.nodes.find { |n| n["id"] == id }
            z_index = style["z_index"] || (orig_node && (orig_node["z_index"] || orig_node.dig("style", "z_index"))) || 0
            
            candidates << {
              id: id,
              bounds: { x: cx, y: cy, w: cw, h: ch },
              node: b_node,
              z_index: z_index.to_i,
              index: index
            }
          end
        end

        # NGUI-P9-3: Overlap resolution using z-index and declaration index
        if candidates.empty?
          return {
            "hit" => false,
            "target" => nil,
            "receipt_id" => "receipt-#{SecureRandom.hex(8) rescue Time.now.to_i}",
            "timestamp" => Time.now.iso8601,
            "non_claims" => scene_tree.non_claims
          }
        end

        candidates.sort_by! { |c| [-c[:z_index], -c[:index]] }
        target = candidates.first
        target_id = target[:id]

        # Extract intent
        orig_node = scene_tree.nodes.find { |n| n["id"] == target_id }
        intent_key = EVENT_TO_INTENT_KEY[event_type]
        intent_payload = orig_node["interaction_intents"]&.[](intent_key)

        matched_intent = nil
        if intent_payload
          # NGUI-P9-7: Validate intent action against whitelist
          action = intent_payload["intent"]
          unless ALLOWED_INTENTS.include?(action)
            raise ValidationError.new("Unknown/unsafe interaction action '#{action}'", check_id: "NGUI-P9-7")
          end

          # Resolve params against slot values
          resolved_params = resolve_params(intent_payload["params"], slot_values)
          matched_intent = {
            "intent" => action,
            "params" => resolved_params
          }
        end

        {
          "hit" => true,
          "target" => {
            "node_id" => target_id,
            "computed_bounds" => target[:bounds],
            "matched_intent" => matched_intent
          },
          "receipt_id" => "receipt-#{SecureRandom.hex(8) rescue Time.now.to_i}",
          "timestamp" => Time.now.iso8601,
          "non_claims" => scene_tree.non_claims
        }

      else # KEYBOARD_EVENTS
        target_id = (event["target"] || event[:target]).to_s
        
        # NGUI-P9-5: Keyboard event routes only to declared focus target
        if target_id.strip.empty?
          raise ValidationError.new("Keyboard event is missing a target node", check_id: "NGUI-P9-5")
        end

        orig_node = scene_tree.nodes.find { |n| n["id"] == target_id }
        unless orig_node
          raise ValidationError.new("Undeclared target node '#{target_id}' for keyboard event", check_id: "NGUI-P9-5")
        end

        bound_node = bound_nodes_map[target_id]
        style = bound_node ? (bound_node["style"] || {}) : {}

        # NGUI-P9-9: unresolved layout box fails closed
        cx = style["x"]
        cy = style["y"]
        cw = style["width"] || style["w"]
        ch = style["height"] || style["h"]
        if cx.nil? || cy.nil? || cw.nil? || ch.nil?
          raise ValidationError.new("Target node '#{target_id}' is missing resolved layout bounds", check_id: "NGUI-P9-9")
        end

        # NGUI-P9-4/5: Hidden or inactive nodes cannot receive focus/keyboard events
        if bound_node && (bound_node["visible"] == false || bound_node["active"] == false)
          raise ValidationError.new("Target node '#{target_id}' is hidden or inactive", check_id: "NGUI-P9-5")
        end

        # Check focus target declaration
        is_focus_target = (orig_node["focus_target"] == true) || 
                          (orig_node["focusable"] == true) ||
                          (style["focus_target"] == true) || 
                          (style["focusable"] == true) ||
                          (orig_node["style"]&.[]("focus_target") == true) ||
                          (orig_node["style"]&.[]("focusable") == true)

        unless is_focus_target
          raise ValidationError.new("Target node '#{target_id}' is not a declared focus target", check_id: "NGUI-P9-5")
        end

        # Extract intent
        intent_key = EVENT_TO_INTENT_KEY[event_type]
        intent_payload = orig_node["interaction_intents"]&.[](intent_key)

        matched_intent = nil
        if intent_payload
          # NGUI-P9-7: Validate intent action
          action = intent_payload["intent"]
          unless ALLOWED_INTENTS.include?(action)
            raise ValidationError.new("Unknown/unsafe interaction action '#{action}'", check_id: "NGUI-P9-7")
          end

          # Resolve params
          resolved_params = resolve_params(intent_payload["params"], slot_values)
          matched_intent = {
            "intent" => action,
            "params" => resolved_params
          }
        end

        {
          "hit" => true,
          "target" => {
            "node_id" => target_id,
            "computed_bounds" => { x: cx, y: cy, w: cw, h: ch },
            "matched_intent" => matched_intent
          },
          "receipt_id" => "receipt-#{SecureRandom.hex(8) rescue Time.now.to_i}",
          "timestamp" => Time.now.iso8601,
          "non_claims" => scene_tree.non_claims
        }
      end
    end

    private

    def self.resolve_params(params, slot_values)
      return nil if params.nil?

      case params
      when Hash
        params.map { |k, v| [k.to_s, resolve_params(v, slot_values)] }.to_h
      when Array
        if params[0] == "slot" && params[1].is_a?(String)
          slot_name = params[1]
          SlotBinder.get_slot_value(slot_values, slot_name)
        else
          params.map { |item| resolve_params(item, slot_values) }
        end
      else
        params
      end
    end
  end
end
