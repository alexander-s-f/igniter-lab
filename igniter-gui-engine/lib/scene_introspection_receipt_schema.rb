# igniter-lab/igniter-gui-engine/lib/scene_introspection_receipt_schema.rb
# frozen_string_literal: true

# Status: experimental · lab-only · no-canon · no-stable-schema · no-performance-claim

require "json"
require_relative "scene_tree"

module IgniterGui
  class SceneIntrospectionReceiptSchema
    ALLOWED_TOP_KEYS = %w[view_id scene_digest node_count nodes timestamp non_claims].freeze
    REQUIRED_TOP_KEYS = %w[view_id scene_digest node_count nodes timestamp non_claims].freeze
    
    REQUIRED_NODE_KEYS = %w[
      id type parent z_index computed_bounds slot_bound
      referenced_slots scoped_slots containment overflow_allowance
      allow_structural_overwrites status
    ].freeze

    MAX_BYTESIZE = 8000

    def self.validate!(receipt_json)
      # 1. Size constraint check (NGUI-P13-9)
      if receipt_json.bytesize > MAX_BYTESIZE
        raise ValidationError.new("Oversized receipt payload (#{receipt_json.bytesize} > #{MAX_BYTESIZE} bytes)", check_id: "NGUI-P13-9")
      end

      # 2. Parse receipt JSON
      begin
        data = JSON.parse(receipt_json)
      rescue => e
        raise ValidationError.new("Malformed receipt JSON: #{e.message}", check_id: "NGUI-P13-8")
      end

      # 3. Reject unknown top-level keys
      data.each_key do |k|
        unless ALLOWED_TOP_KEYS.include?(k)
          raise ValidationError.new("Unknown top-level receipt key: '#{k}'", check_id: "NGUI-P13-8")
        end
      end

      # 4. Check required top-level keys
      REQUIRED_TOP_KEYS.each do |k|
        unless data.key?(k)
          raise ValidationError.new("Missing required top-level key: '#{k}'", check_id: "NGUI-P13-8")
        end
      end

      # Validate type constraints of top-level keys
      unless data["view_id"].is_a?(String)
        raise ValidationError.new("view_id must be a String", check_id: "NGUI-P13-8")
      end
      unless data["scene_digest"].is_a?(String)
        raise ValidationError.new("scene_digest must be a String", check_id: "NGUI-P13-8")
      end
      unless data["node_count"].is_a?(Integer)
        raise ValidationError.new("node_count must be an Integer", check_id: "NGUI-P13-8")
      end
      unless data["nodes"].is_a?(Hash)
        raise ValidationError.new("nodes must be a Hash", check_id: "NGUI-P13-8")
      end
      unless data["timestamp"].is_a?(String)
        raise ValidationError.new("timestamp must be a String", check_id: "NGUI-P13-8")
      end
      unless data["non_claims"].is_a?(Array)
        raise ValidationError.new("non_claims must be an Array", check_id: "NGUI-P13-8")
      end

      # 5. Validate each node entry
      data["nodes"].each do |node_id, node_data|
        unless node_data.is_a?(Hash)
          raise ValidationError.new("Node metadata for '#{node_id}' must be a Hash", check_id: "NGUI-P13-8")
        end

        # Reject unknown keys in node metadata
        node_data.each_key do |k|
          unless REQUIRED_NODE_KEYS.include?(k)
            raise ValidationError.new("Unknown key in node '#{node_id}' metadata: '#{k}'", check_id: "NGUI-P13-8")
          end
        end

        # Check required node keys
        REQUIRED_NODE_KEYS.each do |k|
          unless node_data.key?(k)
            raise ValidationError.new("Missing required key in node '#{node_id}': '#{k}'", check_id: "NGUI-P13-8")
          end
        end

        # Type constraints validation per node field
        unless node_data["id"] == node_id
          raise ValidationError.new("Mismatched node ID in metadata for '#{node_id}'", check_id: "NGUI-P13-8")
        end
        unless node_data["type"].is_a?(String)
          raise ValidationError.new("Node type in '#{node_id}' must be a String", check_id: "NGUI-P13-8")
        end
        if node_data["parent"] && !node_data["parent"].is_a?(String)
          raise ValidationError.new("Node parent in '#{node_id}' must be a String or nil", check_id: "NGUI-P13-8")
        end
        unless node_data["z_index"].is_a?(Integer)
          raise ValidationError.new("z_index in '#{node_id}' must be an Integer", check_id: "NGUI-P13-8")
        end

        bounds = node_data["computed_bounds"]
        if bounds
          unless bounds.is_a?(Hash)
            raise ValidationError.new("computed_bounds in '#{node_id}' must be a Hash or nil", check_id: "NGUI-P13-8")
          end
          %w[x y w h].each do |bk|
            val = bounds[bk] || bounds[bk.to_sym]
            unless val.is_a?(Numeric)
              raise ValidationError.new("computed_bounds key '#{bk}' in '#{node_id}' must be Numeric", check_id: "NGUI-P13-8")
            end
          end
        end

        unless [true, false].include?(node_data["slot_bound"])
          raise ValidationError.new("slot_bound in '#{node_id}' must be a Boolean", check_id: "NGUI-P13-8")
        end
        unless node_data["referenced_slots"].is_a?(Array)
          raise ValidationError.new("referenced_slots in '#{node_id}' must be an Array", check_id: "NGUI-P13-8")
        end
        unless node_data["scoped_slots"].is_a?(Array)
          raise ValidationError.new("scoped_slots in '#{node_id}' must be an Array", check_id: "NGUI-P13-8")
        end
        unless %w[contained overflow N/A].include?(node_data["containment"])
          raise ValidationError.new("Invalid containment value in '#{node_id}'", check_id: "NGUI-P13-8")
        end
        unless %w[allow clip none].include?(node_data["overflow_allowance"])
          raise ValidationError.new("Invalid overflow_allowance value in '#{node_id}'", check_id: "NGUI-P13-8")
        end
        unless [true, false].include?(node_data["allow_structural_overwrites"])
          raise ValidationError.new("allow_structural_overwrites in '#{node_id}' must be a Boolean", check_id: "NGUI-P13-8")
        end
        unless %w[active skip].include?(node_data["status"])
          raise ValidationError.new("Invalid status value in '#{node_id}'", check_id: "NGUI-P13-8")
        end
      end

      # 6. Verify value-free structure (preventing raw SlotValues leaks)
      data["nodes"].each do |node_id, node_data|
        # Verify slot references arrays only contain slot strings, not hashes or payloads
        node_data["referenced_slots"].each do |slot_name|
          unless slot_name.is_a?(String)
            raise ValidationError.new("Referenced slot name must be a String in '#{node_id}'", check_id: "NGUI-P13-8")
          end
        end
        node_data["scoped_slots"].each do |slot_name|
          unless slot_name.is_a?(String)
            raise ValidationError.new("Scoped slot name must be a String in '#{node_id}'", check_id: "NGUI-P13-8")
          end
        end
      end

      true
    end
  end
end
