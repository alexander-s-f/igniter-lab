# igniter-lab/igniter-gui-engine/lib/headless_reactive_loop.rb
# frozen_string_literal: true

# Status: experimental · lab-only · no-canon · no-stable-schema · no-performance-claim

require "json"
require "time"
require "securerandom"
require_relative "scene_tree"
require_relative "layout_resolver"
require_relative "slot_binder"
require_relative "timeline_resolver"
require_relative "vector_renderer"
require_relative "event_dispatcher"

module IgniterGui
  class HeadlessReactiveLoop
    attr_reader :scene_tree, :slot_values, :layout_result, :history, :event_count, :frame_count

    def initialize(scene_tree, initial_slots = {}, options = {})
      @scene_tree = scene_tree
      @slot_values = {}
      
      # Clone initial slots safely
      initial_slots.each { |k, v| @slot_values[k.to_s] = v }

      @max_events = options[:max_events] || 10
      @max_frames = options[:max_frames] || 60
      
      @event_count = 0
      @frame_count = 0
      @history = []

      # Initial root-down layout resolution pass
      recalculate_layout!
    end

    def recalculate_layout!
      # 1. Create a deep copy of scene_tree nodes data
      cloned_nodes = JSON.parse(JSON.generate(@scene_tree.nodes))
      
      # 2. Evaluate and apply display rules to the cloned nodes using current slot_values
      cloned_nodes.each do |node|
        if node["display_rules"].is_a?(Array)
          node["display_rules"].each do |rule|
            rule_type = rule[0]
            if rule_type == "style"
              condition = rule[1]
              on_true_patch = rule[2]
              on_false_patch = rule[3]

              res = SlotBinder.evaluate_expr(condition, @slot_values)
              patch = res ? on_true_patch : on_false_patch

              if patch.is_a?(Hash)
                patch.each do |k, v|
                  k_str = k.to_s
                  if k_str == "visible"
                    node["visible"] = (v == true)
                  elsif k_str == "active"
                    node["active"] = (v == true)
                  else
                    node["style"] ||= {}
                    node["style"][k_str] = v
                  end
                end
              end
            elsif rule_type == "match"
              subject = rule[1]
              cases = rule[2]
              default_patch = rule[3]

              val = SlotBinder.evaluate_expr(subject, @slot_values)
              val_str = val.to_s
              patch = cases.key?(val_str) ? cases[val_str] : default_patch

              if patch.is_a?(Hash)
                patch.each do |k, v|
                  k_str = k.to_s
                  if k_str == "visible"
                    node["visible"] = (v == true)
                  elsif k_str == "active"
                    node["active"] = (v == true)
                  else
                    node["style"] ||= {}
                    node["style"][k_str] = v
                  end
                end
              end
            end
          end
        end
      end

      # 3. Create a temporary SceneTree with the cloned nodes so we don't mutate the original @scene_tree
      temp_scene_data = {
        "view_id" => @scene_tree.view_id,
        "canvas" => @scene_tree.canvas,
        "slots" => @scene_tree.slots,
        "non_claims" => @scene_tree.non_claims,
        "nodes" => cloned_nodes
      }
      temp_scene = SceneTree.new(temp_scene_data)
      
      # 4. Resolve layout using the temp scene
      resolver = LayoutResolver.new(temp_scene)
      temp_layout_result = resolver.resolve!

      # 5. Map the layout result back to the original scene tree's digest
      @layout_result = temp_layout_result.merge("scene_digest" => @scene_tree.digest)
    end

    # Process an event input through dispatch and state reduction
    def process_event(event)
      # 1. Event batch count limit check
      @event_count += 1
      if @event_count > @max_events
        raise ValidationError.new("Event batch limit exceeded (max: #{@max_events})", check_id: "NGUI-P10-9")
      end

      # 2. Dispatch event using current layout and slot values
      receipt = EventDispatcher.dispatch(@layout_result, @scene_tree, @slot_values, event)

      # 3. State reducer: update local UIState/SlotValues if intent matched
      if receipt["hit"] && receipt["target"] && receipt["target"]["matched_intent"]
        matched_intent = receipt["target"]["matched_intent"]
        reduce_state!(matched_intent)
        
        # 4. State/slot update triggers root-down layout recalculation
        recalculate_layout!
      end

      # Update receipt hit target positioning based on recalculated layout bounds (if target hit)
      if receipt["hit"] && receipt["target"]
        node_id = receipt["target"]["node_id"]
        # Find new resolved bounding coordinates from recalculated layout result
        resolved_node = @layout_result["resolved_nodes"].find { |n| (n["id"] || n[:id]) == node_id }
        if resolved_node && resolved_node["computed_bounds"]
          receipt["target"]["computed_bounds"] = resolved_node["computed_bounds"]
        end
      end

      @history << {
        "event" => event,
        "receipt" => receipt,
        "state_after" => @slot_values.dup
      }

      receipt
    end

    # Render a frame and regenerate vector output
    def render_frame(time_ms = 0, animation_manifest = nil, source_receipt_id: "rcpt-reactive-loop")
      # 1. Frame count limit check
      @frame_count += 1
      if @frame_count > @max_frames
        raise ValidationError.new("Frame count limit exceeded (max: #{@max_frames})", check_id: "NGUI-P10-9")
      end

      # 2. Bind layout result, scene tree, and slot values
      bind_res = SlotBinder.bind(@layout_result, @scene_tree, @slot_values, strict_binding: true)
      bound_scene = bind_res[:bound_scene]

      # 3. Resolve animations if manifest provided
      if animation_manifest
        bound_scene = TimelineResolver.resolve(bound_scene, animation_manifest, time_ms)
      end

      # 4. Generate drawing primitives and SVG code
      render_res = VectorRenderer.render(bound_scene, source_receipt_id: source_receipt_id)
      
      {
        "bound_scene" => bound_scene,
        "vector" => render_res[:vector],
        "svg" => render_res[:svg],
        "receipt" => render_res[:receipt]
      }
    end

    private

    # Inert local state reducer
    def reduce_state!(matched_intent)
      action = matched_intent["intent"]
      params = matched_intent["params"] || {}

      case action
      when "select_tab"
        tab_id = params["tab_id"]
        if tab_id.nil? || !tab_id.is_a?(String)
          raise ValidationError.new("Invalid tab_id for select_tab: #{tab_id.inspect}", check_id: "NGUI-P10-7")
        end
        @slot_values["tab"] = tab_id

      when "toggle_sidebar"
        sidebar_id = params["sidebar_id"]
        if sidebar_id.nil? || !sidebar_id.is_a?(String)
          raise ValidationError.new("Invalid sidebar_id for toggle_sidebar: #{sidebar_id.inspect}", check_id: "NGUI-P10-7")
        end
        @slot_values["sidebar_active"] = !@slot_values["sidebar_active"]

      when "submit_form"
        # NGUI-P10-6: submit_form remains inert receipt only, no VM execution
        # Ensure we do not invoke any VM, contracts, network, or storage

      when "close_modal"
        @slot_values["modal_open"] = false

      else
        raise ValidationError.new("Unsupported reducer action '#{action}'", check_id: "NGUI-P10-7")
      end
    end
  end
end
