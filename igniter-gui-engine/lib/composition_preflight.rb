# igniter-lab/igniter-gui-engine/lib/composition_preflight.rb
# frozen_string_literal: true

# Status: experimental · lab-only · no-canon · no-stable-schema · no-performance-claim

require "json"
require "time"
require_relative "scene_tree"

module IgniterGui
  class CompositionPreflight
    def self.preflight(bound_scene)
      # 1. Parse if string
      scene = bound_scene.is_a?(String) ? JSON.parse(bound_scene) : bound_scene

      # Build node lookup map
      nodes_by_id = {}
      scene["bound_nodes"].each { |n| nodes_by_id[n["id"]] = n }

      # 2. Parent reference and cycle checks
      scene["bound_nodes"].each do |node|
        parent_id = node["parent"]
        next if parent_id.nil? || parent_id.to_s.strip.empty?

        # NGUI-P7-11: Reject missing parent refs
        unless nodes_by_id.key?(parent_id)
          raise ValidationError.new("Parent node '#{parent_id}' does not exist for node '#{node["id"]}'", check_id: "NGUI-P7-11")
        end

        # NGUI-P7-12: Reject cyclic parent references
        visited = {}
        curr_id = node["id"]
        while curr_id
          if visited[curr_id]
            raise ValidationError.new("Cyclic parent reference detected involving node '#{curr_id}'", check_id: "NGUI-P7-12")
          end
          visited[curr_id] = true
          curr_parent = nodes_by_id[curr_id]["parent"]
          curr_id = (curr_parent.nil? || curr_parent.to_s.strip.empty?) ? nil : curr_parent
        end
      end

      # 3. NGUI-P7-13: Validate composite subview boundaries
      scene["bound_nodes"].each do |node|
        style = node["style"] || {}
        nx = style["x"]
        ny = style["y"]
        nw = style["width"] || style["w"]
        nh = style["height"] || style["h"]

        # Only validate nodes that have computed coordinates
        next if nx.nil? || ny.nil? || nw.nil? || nh.nil?

        # Traverse up hierarchy to check any parent of type "subview"
        curr = node
        while curr
          parent_id = curr["parent"]
          break if parent_id.nil? || parent_id.to_s.strip.empty?
          
          parent_node = nodes_by_id[parent_id]
          break unless parent_node

          if parent_node["type"] == "subview"
            p_layout = parent_node["layout"] || {}
            p_style = parent_node["style"] || {}
            
            overflow_allowed = %w[allow scroll].include?(p_layout["overflow"].to_s) || 
                               %w[allow scroll].include?(p_style["overflow"].to_s)
            
            unless overflow_allowed
              px = p_style["x"]
              py = p_style["y"]
              pw = p_style["width"] || p_style["w"]
              ph = p_style["height"] || p_style["h"]

              # Subview boundary box validation
              if px.nil? || py.nil? || pw.nil? || ph.nil?
                raise ValidationError.new("Subview node '#{parent_id}' is missing computed layout bounds", check_id: "NGUI-P7-13")
              end

              # Descendant must lie geometrically inside the subview boundaries
              unless nx >= px && (nx + nw) <= (px + pw) && ny >= py && (ny + nh) <= (py + ph)
                raise ValidationError.new("Node '#{node["id"]}' overflows composite subview boundary of '#{parent_id}'", check_id: "NGUI-P7-13")
              end
            end
          end

          curr = parent_node
        end
      end

      # Emit receipt
      {
        "preflight" => true,
        "scene_digest" => scene["scene_digest"],
        "diagnostic_code" => "SUCCESS",
        "timestamp" => Time.now.iso8601,
        "non_claims" => scene["non_claims"]
      }
    end
  end
end
