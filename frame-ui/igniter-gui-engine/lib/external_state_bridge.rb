# igniter-lab/igniter-gui-engine/lib/external_state_bridge.rb
# frozen_string_literal: true

# Status: experimental · lab-only · no-canon · no-stable-schema · no-performance-claim

require "json"
require "time"
require_relative "scene_tree"
require_relative "headless_reactive_loop"

module IgniterGui
  class ExternalStateBridge
    ALLOWED_SOURCES = %w[vm_trace tbackend].freeze
    ALLOWED_STATUSES = %w[success completed].freeze

    def self.apply_update(reactive_loop, envelope_json)
      # 1. Size check (NGUI-P11-9)
      if envelope_json.bytesize > 5000
        raise ValidationError.new("Oversized external state payload (#{envelope_json.bytesize} > 5000 bytes)", check_id: "NGUI-P11-9")
      end

      # 2. Parse envelope
      begin
        envelope = JSON.parse(envelope_json)
      rescue => e
        raise ValidationError.new("Malformed external state envelope: #{e.message}", check_id: "NGUI-P11-9")
      end

      # 3. Required fields validation (NGUI-P11-9)
      %w[envelope_version source_receipt_id source_kind status view_id scene_digest slot_updates].each do |k|
        unless envelope.key?(k)
          raise ValidationError.new("Missing required envelope field: '#{k}'", check_id: "NGUI-P11-9")
        end
      end

      # Version check
      unless envelope["envelope_version"] == "V0"
        raise ValidationError.new("Unsupported envelope version: '#{envelope["envelope_version"]}'", check_id: "NGUI-P11-9")
      end

      # 4. Unknown source/status vocabulary check (NGUI-P11-10)
      unless ALLOWED_SOURCES.include?(envelope["source_kind"])
        raise ValidationError.new("Unknown source kind: '#{envelope["source_kind"]}'", check_id: "NGUI-P11-10")
      end

      unless ALLOWED_STATUSES.include?(envelope["status"])
        raise ValidationError.new("Unknown status: '#{envelope["status"]}'", check_id: "NGUI-P11-10")
      end

      # 5. Digest and view_id mismatch check (NGUI-P11-8)
      scene_tree = reactive_loop.scene_tree
      unless envelope["view_id"] == scene_tree.view_id
        raise ValidationError.new("View ID mismatch: envelope=#{envelope["view_id"]}, scene=#{scene_tree.view_id}", check_id: "NGUI-P11-8")
      end

      unless envelope["scene_digest"] == scene_tree.digest
        raise ValidationError.new("Stale scene digest in envelope: #{envelope["scene_digest"]} != #{scene_tree.digest}", check_id: "NGUI-P11-8")
      end

      # 6. Scoped slot update resolution (NGUI-P11-11)
      scope = envelope["scope"]
      updates = {}
      
      envelope["slot_updates"].each do |k, v|
        resolved_key = scope && !scope.strip.empty? ? "#{scope}.#{k}" : k.to_s
        
        # Undeclared slot check (NGUI-P11-6)
        unless scene_tree.slots.key?(resolved_key)
          raise ValidationError.new("Undeclared slot parameter '#{resolved_key}'", check_id: "NGUI-P11-6")
        end

        # Slot type validation (NGUI-P11-7)
        slot_def = scene_tree.slots[resolved_key]
        declared_type = slot_def["type"]
        
        case declared_type
        when "integer"
          unless v.is_a?(Integer)
            raise ValidationError.new("Type mismatch for slot '#{resolved_key}': expected Integer, got #{v.class}", check_id: "NGUI-P11-7")
          end
        when "boolean"
          unless v == true || v == false
            raise ValidationError.new("Type mismatch for slot '#{resolved_key}': expected Boolean, got #{v.class}", check_id: "NGUI-P11-7")
          end
        when "string"
          unless v.is_a?(String)
            raise ValidationError.new("Type mismatch for slot '#{resolved_key}': expected String, got #{v.class}", check_id: "NGUI-P11-7")
          end
        end

        updates[resolved_key] = v
      end

      # 7. Apply updates to the loop's slot values
      updates.each do |k, v|
        reactive_loop.slot_values[k] = v
      end

      # Trigger layout recalculation
      reactive_loop.recalculate_layout!

      # Return bridge receipt with lineage information
      {
        "ingress" => true,
        "source_receipt_id" => envelope["source_receipt_id"],
        "source_kind" => envelope["source_kind"],
        "status" => envelope["status"],
        "scope" => scope,
        "applied_updates" => updates,
        "scene_digest" => scene_tree.digest,
        "timestamp" => Time.now.iso8601,
        "non_claims" => scene_tree.non_claims
      }
    end
  end
end
