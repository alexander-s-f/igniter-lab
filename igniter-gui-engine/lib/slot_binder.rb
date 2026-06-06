# igniter-lab/igniter-gui-engine/lib/slot_binder.rb
# frozen_string_literal: true

# Status: experimental · lab-only · no-canon · no-stable-schema · no-performance-claim

require_relative "scene_tree"

module IgniterGui
  class SlotBinder
    def self.get_slot_value(slot_values, name)
      if slot_values.key?(name)
        slot_values[name]
      elsif slot_values.key?(name.to_sym)
        slot_values[name.to_sym]
      else
        nil
      end
    end

    # Valid operators list and argument expectations
    VALID_OPERATORS = %w[slot eq gt lt not].freeze

    # Allowed styling property keys
    VALID_STYLE_KEYS = %w[
      x y width height w h fill stroke opacity visible active font size text_color rx ry r border_color border_width color background
    ].freeze

    # Keys that are structural and cannot be overwritten unless allowed explicitly
    STRUCTURAL_KEYS = %w[
      x y width height w h margin padding layout
    ].freeze


    def self.bind(layout_result, scene_tree, slot_values, source_receipt_id: nil, strict_binding: true)
      # 1. Digest consistency check
      layout_digest = layout_result["scene_digest"] || layout_result[:scene_digest]
      if layout_digest != scene_tree.digest
        raise ValidationError.new("Stale scene/layout digest: layout=#{layout_digest}, scene=#{scene_tree.digest}", check_id: "NGUI-P3-9")
      end

      # 2. Payload size guard (NGUI-P4-9)
      max_slots = 50
      max_string_len = 1000
      max_serialized_size = 5000

      if slot_values.size > max_slots
        raise ValidationError.new("SlotValues payload has too many keys (#{slot_values.size} > #{max_slots})", check_id: "NGUI-P4-9")
      end

      slot_values.each do |k, v|
        if v.is_a?(String) && v.bytesize > max_string_len
          raise ValidationError.new("SlotValue for key '#{k}' exceeds maximum string size (#{v.bytesize} > #{max_string_len} bytes)", check_id: "NGUI-P4-9")
        end
      end

      begin
        serialized = JSON.generate(slot_values)
        if serialized.bytesize > max_serialized_size
          raise ValidationError.new("SlotValues payload serialized size exceeds limit (#{serialized.bytesize} > #{max_serialized_size} bytes)", check_id: "NGUI-P4-9")
        end
      rescue => e
        raise ValidationError.new("SlotValues payload is not serializable: #{e.message}", check_id: "NGUI-P4-9")
      end

      # 3. Validate SlotValues contains only declared slot keys
      slot_values.each_key do |key|
        next if key.to_s == "non_claims"
        unless scene_tree.slots.key?(key.to_s)
          raise ValidationError.new("SlotValues contains undeclared slot key '#{key}'", check_id: "NGUI-P3-6")
        end
      end

      # 4. Validate slot value types against declared metadata
      scene_tree.slots.each do |slot_name, metadata|
        next unless slot_values.key?(slot_name) || slot_values.key?(slot_name.to_sym)
        val = get_slot_value(slot_values, slot_name)
        declared_type = metadata["type"]

        case declared_type
        when "integer"
          unless val.is_a?(Integer)
            raise ValidationError.new("Type mismatch for slot '#{slot_name}': expected Integer, got #{val.class}", check_id: "NGUI-P3-8")
          end
        when "boolean"
          unless val == true || val == false
            raise ValidationError.new("Type mismatch for slot '#{slot_name}': expected Boolean, got #{val.class}", check_id: "NGUI-P3-8")
          end
        when "string"
          unless val.is_a?(String)
            raise ValidationError.new("Type mismatch for slot '#{slot_name}': expected String, got #{val.class}", check_id: "NGUI-P3-8")
          end
        end
      end

      # 5. Strict binding mode validation & Structural display rule validation (NGUI-P4-4, NGUI-P4-5, NGUI-P4-6, NGUI-P4-7, NGUI-P4-8)
      scene_tree.nodes.each do |node|
        if node["display_rules"].is_a?(Array)
          node["display_rules"].each do |rule|
            validate_display_rule_structure!(node, rule)

            if strict_binding
              find_slot_refs_in_rule(rule).each do |slot_name|
                unless scene_tree.slots.key?(slot_name)
                  raise ValidationError.new("Undeclared slot reference '#{slot_name}' in strict binding mode", check_id: "NGUI-P3-7")
                end
              end
            end
          end
        end
      end

      # 6. Bind and evaluate layout nodes
      resolved_nodes = layout_result["resolved_nodes"] || layout_result[:resolved_nodes]
      nodes_by_id = {}
      scene_tree.nodes.each { |n| nodes_by_id[n["id"]] = n }

      bound_nodes = resolved_nodes.map do |res_node|
        id = res_node["id"] || res_node[:id]
        orig_node = nodes_by_id[id]

        # Start with original node style and computed bounds
        style = (orig_node["style"] || {}).dup
        computed_bounds = res_node["computed_bounds"] || res_node[:computed_bounds]
        
        # Add basic computed bounds to styles for vector scene representation
        style["x"] = computed_bounds["x"] || computed_bounds[:x]
        style["y"] = computed_bounds["y"] || computed_bounds[:y]
        style["width"] = computed_bounds["w"] || computed_bounds[:w]
        style["height"] = computed_bounds["h"] || computed_bounds[:h]

        visible = true
        active = true

        # Evaluate display rules
        if orig_node["display_rules"].is_a?(Array)
          orig_node["display_rules"].each do |rule|
            rule_type = rule[0]
            if rule_type == "style"
              condition = rule[1]
              on_true_patch = rule[2]
              on_false_patch = rule[3]

              res = evaluate_expr(condition, slot_values)
              patch = res ? on_true_patch : on_false_patch

              if patch.is_a?(Hash)
                patch.each do |k, v|
                  k_str = k.to_s
                  if k_str == "visible"
                    visible = (v == true)
                  elsif k_str == "active"
                    active = (v == true)
                  else
                    style[k_str] = v
                  end
                end
              end
            elsif rule_type == "match"
              subject = rule[1]
              cases = rule[2]
              default_patch = rule[3]

              val = evaluate_expr(subject, slot_values)
              val_str = val.to_s
              patch = cases.key?(val_str) ? cases[val_str] : default_patch

              if patch.is_a?(Hash)
                patch.each do |k, v|
                  k_str = k.to_s
                  if k_str == "visible"
                    visible = (v == true)
                  elsif k_str == "active"
                    active = (v == true)
                  else
                    style[k_str] = v
                  end
                end
              end
            end
          end
        end

        # Handle text content substitution
        content = orig_node["content"]
        if orig_node["type"] == "text" && content.is_a?(String)
          content = content.gsub(/\{slot:([^\}]+)\}/) do
            slot_name = $1
            # Check strict mode for inline placeholders
            if strict_binding && !scene_tree.slots.key?(slot_name)
              raise ValidationError.new("Undeclared slot reference '#{slot_name}' in text placeholder under strict mode", check_id: "NGUI-P3-7")
            end
            val = get_slot_value(slot_values, slot_name)
            val.nil? ? "" : val.to_s
          end
        end

        bound_node = {
          "id" => id,
          "type" => orig_node["type"],
          "parent" => orig_node["parent"],
          "style" => style,
          "visible" => visible,
          "active" => active
        }
        bound_node["content"] = content if orig_node["type"] == "text"
        bound_node["fill"] = orig_node["fill"] if orig_node["fill"]
        bound_node["rx"] = orig_node["rx"] if orig_node["rx"]
        bound_node["ry"] = orig_node["ry"] if orig_node["ry"]
        bound_node["r"] = orig_node["r"] if orig_node["r"]

        bound_node
      end

      bound_scene = {
        "view_id" => scene_tree.view_id,
        "scene_digest" => scene_tree.digest,
        "canvas" => scene_tree.canvas,
        "bound_nodes" => bound_nodes,
        "non_claims" => scene_tree.non_claims
      }

      receipt = {
        "hit" => false, # Slot binding does not run hit testing
        "bound" => true,
        "scene_digest" => scene_tree.digest,
        "source_receipt_id" => source_receipt_id,
        "diagnostic_code" => "SUCCESS",
        "timestamp" => Time.now.iso8601,
        "non_claims" => scene_tree.non_claims
      }

      { bound_scene: bound_scene, receipt: receipt }
    end

    private

    def self.validate_display_rule_structure!(node, rule)
      unless rule.is_a?(Array)
        raise ValidationError.new("Display rule must be an Array, got #{rule.class}", check_id: "NGUI-P4-4")
      end

      if rule.empty?
        raise ValidationError.new("Display rule cannot be empty", check_id: "NGUI-P4-4")
      end

      rule_type = rule[0]
      unless %w[style match].include?(rule_type)
        raise ValidationError.new("Unsupported display rule type '#{rule_type}'", check_id: "NGUI-P4-5")
      end

      case rule_type
      when "style"
        if rule.size != 4
          raise ValidationError.new("Style display rule must have exactly 4 elements, got #{rule.size}", check_id: "NGUI-P4-4")
        end

        condition = rule[1]
        validate_expression!(condition)

        on_true_patch = rule[2]
        on_false_patch = rule[3]

        validate_style_patch!(node, on_true_patch) if on_true_patch
        validate_style_patch!(node, on_false_patch) if on_false_patch

      when "match"
        if rule.size != 4
          raise ValidationError.new("Match display rule must have exactly 4 elements, got #{rule.size}", check_id: "NGUI-P4-4")
        end

        subject = rule[1]
        validate_expression!(subject)

        cases = rule[2]
        unless cases.is_a?(Hash)
          raise ValidationError.new("Match display rule cases must be a Hash, got #{cases.class}", check_id: "NGUI-P4-4")
        end

        cases.each do |k, patch|
          validate_style_patch!(node, patch) if patch
        end

        default_patch = rule[3]
        validate_style_patch!(node, default_patch) if default_patch
      end
    end

    def self.validate_expression!(expr)
      if expr.is_a?(Array)
        if expr.empty?
          raise ValidationError.new("Expression array cannot be empty", check_id: "NGUI-P4-3")
        end

        op = expr[0]
        unless op.is_a?(String)
          raise ValidationError.new("Expression operator must be a String, got #{op.class}", check_id: "NGUI-P4-3")
        end

        unless VALID_OPERATORS.include?(op)
          raise ValidationError.new("Unknown expression operator '#{op}'", check_id: "NGUI-P4-2")
        end

        case op
        when "slot"
          if expr.size != 2
            raise ValidationError.new("Operator 'slot' expects exactly 1 argument, got #{expr.size - 1}", check_id: "NGUI-P4-3")
          end
          unless expr[1].is_a?(String)
            raise ValidationError.new("Operator 'slot' argument must be a String slot name, got #{expr[1].class}", check_id: "NGUI-P4-3")
          end
        when "not"
          if expr.size != 2
            raise ValidationError.new("Operator 'not' expects exactly 1 argument, got #{expr.size - 1}", check_id: "NGUI-P4-3")
          end
          validate_expression!(expr[1])
        when "eq", "gt", "lt"
          if expr.size != 3
            raise ValidationError.new("Operator '#{op}' expects exactly 2 arguments, got #{expr.size - 1}", check_id: "NGUI-P4-3")
          end
          validate_expression!(expr[1])
          validate_expression!(expr[2])
        end
      else
        # Literal validation
        unless expr.nil? || expr.is_a?(Integer) || expr.is_a?(Float) || expr.is_a?(String) || expr == true || expr == false
          raise ValidationError.new("Invalid literal expression type: #{expr.class}", check_id: "NGUI-P4-3")
        end
      end
    end

    def self.validate_style_patch!(node, patch)
      unless patch.is_a?(Hash)
        raise ValidationError.new("Style patch must be a Hash, got #{patch.class}", check_id: "NGUI-P4-4")
      end

      patch.each do |k, v|
        k_str = k.to_s

        # NGUI-P4-6: Unsafe style patch key
        unless VALID_STYLE_KEYS.include?(k_str)
          raise ValidationError.new("Unsafe or unknown style patch key '#{k_str}'", check_id: "NGUI-P4-6")
        end

        # NGUI-P4-7: Structural bound overwrite is blocked by default
        if STRUCTURAL_KEYS.include?(k_str)
          unless node["allow_structural_overwrites"] == true
            raise ValidationError.new("Structural bound override for key '#{k_str}' is blocked by default on node '#{node["id"]}'", check_id: "NGUI-P4-7")
          end
        end

        # NGUI-P4-8: Invalid patch value type
        validate_style_value_type!(k_str, v)
      end
    end

    def self.validate_style_value_type!(key, val)
      case key
      when "visible", "active"
        unless val == true || val == false
          raise ValidationError.new("Style value for '#{key}' must be a Boolean, got #{val.class}", check_id: "NGUI-P4-8")
        end
      when "opacity"
        unless val.is_a?(Numeric)
          raise ValidationError.new("Style value for '#{key}' must be Numeric, got #{val.class}", check_id: "NGUI-P4-8")
        end
        unless val >= 0.0 && val <= 1.0
          raise ValidationError.new("Style value for '#{key}' must be between 0.0 and 1.0, got #{val}", check_id: "NGUI-P4-8")
        end
      when "x", "y", "width", "height", "w", "h", "size", "rx", "ry", "r", "border_width"
        unless val.is_a?(Numeric)
          raise ValidationError.new("Style value for '#{key}' must be Numeric, got #{val.class}", check_id: "NGUI-P4-8")
        end
      when "fill", "stroke", "border_color", "color", "background"
        unless val.is_a?(String)
          raise ValidationError.new("Style value for '#{key}' must be a String, got #{val.class}", check_id: "NGUI-P4-8")
        end
        unless val.match?(/\A#(?:[0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})\z/)
          raise ValidationError.new("Style value for '#{key}' must be a valid hex color format, got '#{val}'", check_id: "NGUI-P4-8")
        end
      when "font", "text_color"
        unless val.is_a?(String)
          raise ValidationError.new("Style value for '#{key}' must be a String, got #{val.class}", check_id: "NGUI-P4-8")
        end
      end
    end

    def self.find_slot_refs_in_rule(expr)
      refs = []
      return refs unless expr.is_a?(Array)

      if expr[0] == "slot" && expr[1].is_a?(String)
        refs << expr[1]
      else
        expr.each do |child|
          refs.concat(find_slot_refs_in_rule(child)) if child.is_a?(Array)
        end
      end
      refs
    end

    def self.evaluate_expr(expr, slot_values)
      return expr unless expr.is_a?(Array)

      op = expr[0]
      case op
      when "slot"
        slot_name = expr[1]
        get_slot_value(slot_values, slot_name)
      when "eq"
        evaluate_expr(expr[1], slot_values) == evaluate_expr(expr[2], slot_values)
      when "gt"
        v1 = evaluate_expr(expr[1], slot_values)
        v2 = evaluate_expr(expr[2], slot_values)
        return false if v1.nil? || v2.nil?
        v1 > v2
      when "lt"
        v1 = evaluate_expr(expr[1], slot_values)
        v2 = evaluate_expr(expr[2], slot_values)
        return false if v1.nil? || v2.nil?
        v1 < v2
      when "not"
        !evaluate_expr(expr[1], slot_values)
      else
        # Literal fallback or unhandled op
        expr
      end
    end
  end
end
