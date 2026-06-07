# igniter-lab/igniter-gui-engine/lib/scene_introspection_exporter.rb
# frozen_string_literal: true

# Status: experimental · lab-only · no-canon · no-stable-schema · no-performance-claim

require "json"
require "time"
require_relative "scene_tree"

module IgniterGui
  class SceneIntrospectionExporter
    ALLOWED_TYPES = %w[container rect rounded_rect circle text subview].freeze

    def self.export(scene_tree, layout_result)
      validate_input!(scene_tree, layout_result)

      nodes_by_id = {}
      scene_tree.nodes.each { |n| nodes_by_id[n["id"]] = n }

      resolved_by_id = {}
      (layout_result["resolved_nodes"] || []).each do |rn|
        resolved_by_id[rn["id"]] = rn
      end

      # Sort node IDs alphabetically for strict determinism
      sorted_node_ids = scene_tree.nodes.map { |n| n["id"] }.sort
      
      nodes_receipt = {}
      mermaid_nodes = []
      mermaid_edges = []

      sorted_node_ids.each do |node_id|
        node = nodes_by_id[node_id]
        resolved = resolved_by_id[node_id]
        
        type = node["type"]
        parent_id = node["parent"]
        z_index = node["z_index"] || node["style"]&.[]("z_index") || 0
        computed_bounds = resolved ? resolved["computed_bounds"] : nil

        # Slot-bound detection
        ref_slots = collect_referenced_slots(node)
        slot_bound = !ref_slots.empty?
        scoped_slots = ref_slots.select { |s| s.include?(".") }

        # Containment & overflow checks
        containment_str = "N/A"
        overflow_allowance = "none"
        if parent_id && nodes_by_id[parent_id]
          parent_node = nodes_by_id[parent_id]
          if parent_node["layout"].is_a?(Hash)
            overflow_allowance = parent_node["layout"]["overflow"] || "none"
          end

          child_box = computed_bounds
          parent_resolved = resolved_by_id[parent_id]
          parent_box = parent_resolved ? parent_resolved["computed_bounds"] : nil

          if child_box && parent_box
            cx = child_box[:x] || child_box["x"]
            cy = child_box[:y] || child_box["y"]
            cw = child_box[:w] || child_box["w"] || child_box[:width] || child_box["width"]
            ch = child_box[:h] || child_box["h"] || child_box[:height] || child_box["height"]
            
            px = parent_box[:x] || parent_box["x"]
            py = parent_box[:y] || parent_box["y"]
            pw = parent_box[:w] || parent_box["w"] || parent_box[:width] || parent_box["width"]
            ph = parent_box[:h] || parent_box["h"] || parent_box[:height] || parent_box["height"]

            if cx && cy && cw && ch && px && py && pw && ph
              if cw == 0 && ch == 0
                containment_str = "contained"
              else
                is_contained = (cx >= px) && (cy >= py) && ((cx + cw) <= (px + pw)) && ((cy + ch) <= (py + ph))
                containment_str = is_contained ? "contained" : "overflow"
              end
            end
          end
        end

        allow_overwrites = node["allow_structural_overwrites"] == true
        
        # Unsupported primitive skip status (skipped in VectorRenderer but valid in SceneTree)
        status = ALLOWED_TYPES.include?(type) ? "active" : "skip"

        # Build node receipt details
        nodes_receipt[node_id] = {
          "id" => node_id,
          "type" => type,
          "parent" => parent_id,
          "z_index" => z_index,
          "computed_bounds" => computed_bounds,
          "slot_bound" => slot_bound,
          "referenced_slots" => ref_slots,
          "scoped_slots" => scoped_slots,
          "containment" => containment_str,
          "overflow_allowance" => overflow_allowance,
          "allow_structural_overwrites" => allow_overwrites,
          "status" => status
        }

        # Build Mermaid label
        label_parts = []
        label_parts << "Node: #{node_id} (#{type})"
        label_parts << "Parent: #{parent_id || 'none'}"
        label_parts << "Z-Index: #{z_index}"
        
        if computed_bounds
          cx = computed_bounds[:x] || computed_bounds["x"]
          cy = computed_bounds[:y] || computed_bounds["y"]
          cw = computed_bounds[:w] || computed_bounds["w"] || computed_bounds[:width] || computed_bounds["width"]
          ch = computed_bounds[:h] || computed_bounds["h"] || computed_bounds[:height] || computed_bounds["height"]
          label_parts << "Bounds: [#{cx}, #{cy}, #{cw}, #{ch}]"
        else
          label_parts << "Bounds: N/A"
        end

        if slot_bound
          label_parts << "Slots: #{ref_slots.join(', ')} (slot-bound)"
        end
        if !scoped_slots.empty?
          label_parts << "Scoped: #{scoped_slots.join(', ')}"
        end

        label_parts << "Containment: #{containment_str}"
        label_parts << "Overflow: #{overflow_allowance}"
        label_parts << "Overwrite: #{allow_overwrites ? 'allowed' : 'blocked'}"
        label_parts << "Status: #{status}"

        # Escaping quotes for Mermaid
        escaped_label = label_parts.join("<br/>").gsub('"', '\\"')
        mermaid_nodes << "  #{node_id}[\"#{escaped_label}\"]"

        if parent_id
          mermaid_edges << { parent: parent_id, child: node_id }
        end
      end

      # Deterministic Mermaid generation
      mermaid_lines = ["flowchart TD"]
      mermaid_nodes.each { |mn| mermaid_lines << mn }

      # Sort edges deterministically
      sorted_edges = mermaid_edges.sort_by { |e| [e[:parent], e[:child]] }
      sorted_edges.each do |e|
        mermaid_lines << "  #{e[:parent]} --> #{e[:child]}"
      end

      mermaid_graph = mermaid_lines.join("\n")

      # Final JSON introspection receipt
      receipt = {
        "view_id" => scene_tree.view_id,
        "scene_digest" => scene_tree.digest,
        "node_count" => scene_tree.nodes.size,
        "nodes" => nodes_receipt,
        "timestamp" => Time.now.iso8601,
        "non_claims" => scene_tree.non_claims
      }

      {
        mermaid: mermaid_graph,
        receipt: receipt
      }
    end

    private

    def self.validate_input!(scene_tree, layout_result)
      if scene_tree.nil? || layout_result.nil?
        raise ValidationError.new("Nil SceneTree or layout result passed", check_id: "NGUI-P12-8")
      end

      # Check view_id mismatch
      if scene_tree.view_id != layout_result["view_id"]
        raise ValidationError.new("View ID mismatch: #{scene_tree.view_id} != #{layout_result['view_id']}", check_id: "NGUI-P12-8")
      end

      # Check digest mismatch
      if scene_tree.digest != layout_result["scene_digest"]
        raise ValidationError.new("Scene digest mismatch: #{scene_tree.digest} != #{layout_result['scene_digest']}", check_id: "NGUI-P12-8")
      end

      seen = {}
      scene_tree.nodes.each do |n|
        id = n["id"]
        if id.nil? || id.to_s.strip.empty?
          raise ValidationError.new("Node missing required field: 'id'", check_id: "NGUI-P12-8")
        end
        if seen[id]
          raise ValidationError.new("Duplicate node ID detected: '#{id}'", check_id: "NGUI-P12-9")
        end
        seen[id] = true

        if n["type"].nil? || n["type"].to_s.strip.empty?
          raise ValidationError.new("Node '#{id}' missing type", check_id: "NGUI-P12-8")
        end
        unless SceneTree::WHITELISTED_TYPES.include?(n["type"])
          raise ValidationError.new("Unsupported primitive type '#{n['type']}' in node '#{id}'", check_id: "NGUI-P12-8")
        end
      end

      # Check for cyclic parent reference using DFS
      adj = Hash.new { |h, k| h[k] = [] }
      scene_tree.nodes.each do |n|
        adj[n["parent"]] << n["id"] if n["parent"]
      end
      
      visited = {}
      rec_stack = {}
      
      dfs = lambda do |node_id|
        visited[node_id] = true
        rec_stack[node_id] = true
        
        adj[node_id].each do |child_id|
          if rec_stack[child_id]
            raise ValidationError.new("Cyclic parent reference detected involving node '#{child_id}'", check_id: "NGUI-P12-9")
          end
          dfs.call(child_id) unless visited[child_id]
        end
        
        rec_stack[node_id] = false
      end
      
      scene_tree.nodes.each do |n|
        dfs.call(n["id"]) unless visited[n["id"]]
      end
    end

    def self.collect_referenced_slots(node)
      slots = []
      
      # 1. Sweep display rules
      if node["display_rules"].is_a?(Array)
        node["display_rules"].each do |rule|
          slots.concat(extract_slots_from_expr(rule))
        end
      end

      # 2. Sweep interaction intents
      if node["interaction_intents"].is_a?(Hash)
        node["interaction_intents"].each do |event, payload|
          if payload.is_a?(Hash) && payload["params"].is_a?(Hash)
            payload["params"].each do |k, v|
              slots.concat(extract_slots_from_expr(v))
            end
          end
        end
      end

      # 3. Sweep text content placeholders: {slot:name}
      if node["content"].is_a?(String)
        node["content"].scan(/\{slot:([^\}]+)\}/).each do |match|
          slots << match[0]
        end
      end

      slots.uniq.sort
    end

    def self.extract_slots_from_expr(expr)
      slots = []
      return slots unless expr.is_a?(Array)

      if expr[0] == "slot" && expr[1].is_a?(String)
        slots << expr[1]
      else
        expr.each do |child|
          slots.concat(extract_slots_from_expr(child)) if child.is_a?(Array)
        end
      end
      slots
    end
  end
end
