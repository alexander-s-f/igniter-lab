# igniter-lab/igniter-gui-engine/lib/scene_tree.rb
# frozen_string_literal: true

# Status: experimental · lab-only · no-canon · no-stable-schema · no-performance-claim

require "json"
require "digest"

module IgniterGui
  class ValidationError < StandardError
    attr_reader :severity, :check_id

    def initialize(msg, severity: :error, check_id: nil)
      super(msg)
      @severity = severity
      @check_id = check_id
    end
  end

  class SceneTree
    WHITELISTED_TYPES = %w[container rect rounded_rect circle text path group subview].freeze
    REQUIRED_NON_CLAIMS = %w[lab-only experimental no-canon no-stable-schema no-performance-claim].freeze

    attr_reader :view_id, :canvas, :slots, :nodes, :non_claims, :digest, :diagnostics

    def initialize(json_data)
      @diagnostics = []
      parse_and_validate!(json_data)
      @digest = compute_digest
    end

    def self.load_file(path)
      unless File.exist?(path)
        raise ValidationError.new("File not found: #{path}", check_id: "NGUI-P1-4")
      end
      
      begin
        content = File.read(path, encoding: "utf-8")
        data = JSON.parse(content)
      rescue JSON::ParserError => e
        raise ValidationError.new("JSON Syntax Error: #{e.message}", check_id: "NGUI-P1-4")
      end

      new(data)
    end

    def valid?
      @diagnostics.none? { |d| d[:severity] == :error }
    end

    def recompute_digest!
      @digest = compute_digest
    end

    private

    def parse_and_validate!(data)
      # 1. Top level structure
      @view_id = data["view_id"]
      raise ValidationError.new("Missing required top-level field: 'view_id'", check_id: "NGUI-P1-4") unless @view_id.is_a?(String)

      @canvas = data["canvas"]
      raise ValidationError.new("Missing required top-level field: 'canvas'", check_id: "NGUI-P1-4") unless @canvas.is_a?(Hash)
      raise ValidationError.new("Canvas missing width/height", check_id: "NGUI-P1-4") unless @canvas["width"].is_a?(Numeric) && @canvas["height"].is_a?(Numeric)

      @slots = data["slots"] || {}
      raise ValidationError.new("Slots must be a Hash", check_id: "NGUI-P1-4") unless @slots.is_a?(Hash)

      @non_claims = data["non_claims"]
      raise ValidationError.new("Missing required top-level field: 'non_claims'", check_id: "NGUI-P1-13") unless @non_claims.is_a?(Array)
      
      missing_claims = REQUIRED_NON_CLAIMS - @non_claims
      unless missing_claims.empty?
        raise ValidationError.new("Missing required non_claims markers: #{missing_claims.join(', ')}", check_id: "NGUI-P1-13")
      end

      @nodes = data["nodes"]
      raise ValidationError.new("Missing required top-level field: 'nodes'", check_id: "NGUI-P1-4") unless @nodes.is_a?(Array)

      # 2. Nodes validation
      seen_ids = {}
      @nodes.each_with_index do |node, idx|
        id = node["id"]
        if id.nil? || id.to_s.strip.empty?
          raise ValidationError.new("Node at index #{idx} is missing required field: 'id'", check_id: "NGUI-P1-4")
        end
        
        id_str = id.to_s
        if seen_ids.key?(id_str)
          raise ValidationError.new("Duplicate node ID detected: '#{id_str}'", check_id: "NGUI-P1-5")
        end
        seen_ids[id_str] = true

        type = node["type"]
        if type.nil? || type.to_s.strip.empty?
          raise ValidationError.new("Node '#{id_str}' is missing required field: 'type'", check_id: "NGUI-P1-4")
        end

        unless WHITELISTED_TYPES.include?(type)
          raise ValidationError.new("Unsupported primitive type '#{type}' in node '#{id_str}'", check_id: "NGUI-P1-7")
        end

        # Validate display rules slot references
        if node["display_rules"].is_a?(Array)
          node["display_rules"].each do |rule|
            validate_display_rule_slots!(id_str, rule)
          end
        end

        # Validate interaction intents
        if node["interaction_intents"].is_a?(Hash)
          validate_interaction_intents!(id_str, node["interaction_intents"])
        end
      end
    end

    def validate_interaction_intents!(node_id, intents)
      whitelisted_events = %w[on_click on_mousedown on_mouseup on_mousemove on_keypress on_keydown on_keyup]
      whitelisted_intents = %w[select_tab toggle_sidebar submit_form close_modal]

      intents.each do |event_kind, intent_payload|
        unless whitelisted_events.include?(event_kind)
          raise ValidationError.new("Unsupported event kind '#{event_kind}' in node '#{node_id}'", check_id: "NGUI-P2-7")
        end

        unless intent_payload.is_a?(Hash) && intent_payload["intent"].is_a?(String)
          raise ValidationError.new("Invalid intent payload format in node '#{node_id}'", check_id: "NGUI-P2-6")
        end

        action = intent_payload["intent"]
        unless whitelisted_intents.include?(action)
          raise ValidationError.new("Unknown/unsafe interaction action '#{action}' in node '#{node_id}'", check_id: "NGUI-P2-6")
        end

        params = intent_payload["params"]
        if params.is_a?(Hash)
          validate_intent_params_slots!(node_id, params)
        end
      end
    end

    def validate_intent_params_slots!(node_id, params)
      params.each do |key, val|
        # Recursively search for slot references in parameter values
        find_slot_refs(val).each do |slot_name|
          unless @slots.key?(slot_name)
            raise ValidationError.new("Interaction intent in node '#{node_id}' references undeclared slot: '#{slot_name}'", check_id: "NGUI-P2-9")
          end
        end
      end
    end

    def validate_display_rule_slots!(node_id, rule)
      return unless rule.is_a?(Array)
      # Recursive sweep for ["slot", "name"]
      find_slot_refs(rule).each do |slot_name|
        unless @slots.key?(slot_name)
          msg = "Node '#{node_id}' display rule references undeclared slot: '#{slot_name}'"
          @diagnostics << { severity: :warning, type: :invalid_slot_reference, message: msg, check_id: "NGUI-P1-8" }
        end
      end
    end

    def find_slot_refs(expr)
      refs = []
      return refs unless expr.is_a?(Array)

      if expr[0] == "slot" && expr[1].is_a?(String)
        refs << expr[1]
      else
        expr.each do |child|
          refs.concat(find_slot_refs(child)) if child.is_a?(Array)
        end
      end
      refs
    end

    # Canonical recursive sort for JSON hashing
    def canonical_sort(val)
      case val
      when Hash
        val.sort.map { |k, v| [k, canonical_sort(v)] }.to_h
      when Array
        val.map { |item| canonical_sort(item) }
      else
        val
      end
    end

    def compute_digest
      canonical_data = {
        "view_id" => @view_id,
        "canvas" => @canvas,
        "slots" => @slots,
        "nodes" => @nodes
      }
      sorted = canonical_sort(canonical_data)
      json_bytes = JSON.generate(sorted)
      "sha256:" + Digest::SHA256.hexdigest(json_bytes)
    end
  end
end
