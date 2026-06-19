# igniter-lab/igniter-gui-engine/lib/vector_renderer.rb
# frozen_string_literal: true

# Status: experimental · lab-only · no-canon · no-stable-schema · no-performance-claim

require "json"
require "time"
require "cgi"
require_relative "scene_tree"
require_relative "composition_preflight"

module IgniterGui
  class VectorRenderer
    COLOR_KEYS = %w[fill stroke border_color text_color background color].freeze
    DRAWABLE_TYPES = %w[rect rounded_rect circle text].freeze
    ALLOWED_TYPES = (%w[container subview] + DRAWABLE_TYPES).freeze

    def self.contains_unsafe_fragments?(str)
      return false if str.nil?
      str_down = str.to_s.downcase
      # Reject quotes, angle brackets
      return true if str.to_s.include?('"') || str.to_s.include?("'") || str.to_s.include?("<") || str.to_s.include?(">")
      # Reject event-handler patterns (e.g. onload, onclick, node_onclick)
      return true if str_down.match?(/(?:\A|[^a-z])on[a-z]+/)
      # Reject javascript: and url()
      return true if str_down.include?("javascript:") || str_down.include?("url(")
      false
    end

    def self.render(bound_scene, source_receipt_id: "rcpt_mock_vm_p2")
      # 1. Parse if string
      scene = bound_scene.is_a?(String) ? JSON.parse(bound_scene) : bound_scene

      # 1.5 Run composition preflight validation
      CompositionPreflight.preflight(scene)

      # Validate canvas
      canvas = scene["canvas"]
      if canvas.nil? || !canvas.is_a?(Hash) || !canvas["width"].is_a?(Numeric) || !canvas["height"].is_a?(Numeric)
        raise ValidationError.new("Invalid canvas size in bound scene", check_id: "NGUI-P6-5")
      end

      # Validate non_claims
      non_claims = scene["non_claims"]
      if non_claims.nil? || !non_claims.is_a?(Array)
        raise ValidationError.new("Missing non_claims metadata", check_id: "NGUI-P6-5")
      end

      # 2. Hardening validations
      nodes = scene["bound_nodes"] || []
      nodes.each do |node|
        type = node["type"]
        id = node["id"]

        # NGUI-P7-3: Unsafe ID rejection (quotes, angle brackets, event handlers)
        if contains_unsafe_fragments?(id)
          raise ValidationError.new("Unsafe node ID '#{id}' detected", check_id: "NGUI-P7-3")
        end

        # NGUI-P7-4: ID format mismatch fails closed (alphanumeric, hyphen, underscore, dot)
        unless id.is_a?(String) && id.match?(/\A[a-zA-Z0-9\-_.]+\z/)
          raise ValidationError.new("Invalid node ID format '#{id}'", check_id: "NGUI-P7-4")
        end

        # NGUI-P6-5: Reject unknown/unsupported primitive types
        unless ALLOWED_TYPES.include?(type)
          raise ValidationError.new("Unsupported primitive type '#{type}' on node '#{id}'", check_id: "NGUI-P6-5")
        end

        style = node["style"] || {}

        # NGUI-P7-5: Unsafe font-family values rejected
        font = style["font"] || style["font_family"]
        if font
          if contains_unsafe_fragments?(font) || font.to_s.include?(";")
            raise ValidationError.new("Unsafe or invalid font-family '#{font}' on node '#{id}'", check_id: "NGUI-P7-5")
          end
        end

        # Validate colors in node and style
        # NGUI-P6-8: invalid color value format fails closed
        COLOR_KEYS.each do |key|
          validate_color_value!(node[key], id) if node.key?(key)
          validate_color_value!(style[key], id) if style.key?(key)
        end

        # NGUI-P6-9: transform validation
        %w[transform_translate_x transform_translate_y transform_scale].each do |k|
          val = style[k]
          if val && !val.is_a?(Numeric)
            raise ValidationError.new("Transform parameter '#{k}' on node '#{id}' must be Numeric", check_id: "NGUI-P6-9")
          end
        end
        
        # NGUI-P7-6 / NGUI-P6-9: Transform validation
        raw_transform = style["transform"]
        if raw_transform
          # If it contains unsafe fragments, report as unsafe under NGUI-P7-6
          if contains_unsafe_fragments?(raw_transform)
            raise ValidationError.new("Unsafe transform attributes on node '#{id}'", check_id: "NGUI-P7-6")
          end
          # If it is just malformed layout format, report under NGUI-P6-9
          unless raw_transform.is_a?(String) && raw_transform.match?(/\A\s*(?:translate\(-?\d+(?:\.\d+)?(?:,\s*-?\d+(?:\.\d+)?)?\)|\s*scale\(-?\d+(?:\.\d+)?\))\s*(?:\s*(?:translate\(-?\d+(?:\.\d+)?(?:,\s*-?\d+(?:\.\d+)?)?\)|\s*scale\(-?\d+(?:\.\d+)?\))\s*)*\z/)
            raise ValidationError.new("Unsupported transform format: '#{raw_transform}' on node '#{id}'", check_id: "NGUI-P6-9")
          end
        end

        # NGUI-P6-6: Layout Box Validation for all drawable primitives
        if DRAWABLE_TYPES.include?(type)
          x = style["x"]
          y = style["y"]
          w = style["width"] || style["w"]
          h = style["height"] || style["h"]

          if x.nil? || y.nil? || w.nil? || h.nil?
            raise ValidationError.new("Missing layout bounds for drawable primitive '#{id}'", check_id: "NGUI-P6-6")
          end
          unless x.is_a?(Numeric) && y.is_a?(Numeric) && w.is_a?(Numeric) && h.is_a?(Numeric)
            raise ValidationError.new("Invalid layout bounds type for drawable primitive '#{id}'", check_id: "NGUI-P6-6")
          end

          # For circle, also validate radius if present
          if type == "circle"
            r = node["r"] || style["r"]
            if r && !r.is_a?(Numeric)
              raise ValidationError.new("Circle radius 'r' must be Numeric on node '#{id}'", check_id: "NGUI-P6-6")
            end
          end
        end

        # NGUI-P6-7: Text HTML/Script injection guard
        if type == "text"
          content = node["content"]
          if content
            unless content.is_a?(String)
              raise ValidationError.new("Text content must be a String on node '#{id}'", check_id: "NGUI-P6-7")
            end
            if content.match?(/<[^>]+>/) || content.downcase.include?("<script")
              raise ValidationError.new("HTML/Script text payload injection detected in text node '#{id}'", check_id: "NGUI-P6-7")
            end
          end
        end
      end

      # 3. Filter visible & active drawable nodes
      candidates = []
      nodes.each_with_index do |node, idx|
        next unless DRAWABLE_TYPES.include?(node["type"])
        next if node["visible"] == false
        next if node["active"] == false
        candidates << { node: node, index: idx }
      end

      # 4. Painter's Algorithm Sorting (z-index ascending, declaration index ascending)
      # NGUI-P6-10: painters algorithm sorting is deterministic
      candidates.sort_by! do |c|
        z = c[:node]["z_index"] || c[:node]["style"]&.[]("z_index") || 0
        [z, c[:index]]
      end

      # 5. Generate primitives representation
      primitives = candidates.map do |c|
        node = c[:node]
        style = node["style"] || {}
        type = node["type"]
        id = node["id"]

        prim = {
          "id" => id,
          "type" => type,
          "fill" => node["fill"] || style["fill"] || nil,
          "stroke" => node["stroke"] || style["stroke"] || nil,
          "stroke_width" => style["stroke_width"] || style["border_width"] || nil,
          "opacity" => style["opacity"] || node["opacity"] || 1.0
        }

        # Handle dimensions/shape specifics
        case type
        when "rect", "rounded_rect"
          prim["x"] = style["x"].to_f
          prim["y"] = style["y"].to_f
          prim["width"] = (style["width"] || style["w"]).to_f
          prim["height"] = (style["height"] || style["h"]).to_f
          
          if type == "rounded_rect"
            prim["rx"] = (node["rx"] || style["rx"] || 0.0).to_f
            prim["ry"] = (node["ry"] || style["ry"] || 0.0).to_f
          end

        when "circle"
          w = (style["width"] || style["w"]).to_f
          h = (style["height"] || style["h"]).to_f
          r = (node["r"] || style["r"] || (w / 2.0)).to_f
          
          prim["cx"] = (style["x"] + w / 2.0).to_f
          prim["cy"] = (style["y"] + h / 2.0).to_f
          prim["r"] = r

        when "text"
          prim["x"] = style["x"].to_f
          prim["y"] = style["y"].to_f
          prim["width"] = (style["width"] || style["w"]).to_f
          prim["height"] = (style["height"] || style["h"]).to_f
          prim["content"] = node["content"] || ""
          prim["font"] = style["font"] || style["font_family"] || "sans-serif"
          prim["size"] = (style["size"] || style["font_size"] || 12.0).to_f
        end

        # Translate translation & scale parameters into SVG transform string
        transform_parts = []
        if style["transform_translate_x"] || style["transform_translate_y"]
          tx = (style["transform_translate_x"] || 0.0).to_f
          ty = (style["transform_translate_y"] || 0.0).to_f
          transform_parts << "translate(#{tx}, #{ty})"
        end
        if style["transform_scale"]
          ts = style["transform_scale"].to_f
          transform_parts << "scale(#{ts})"
        end
        if style["transform"]
          transform_parts << style["transform"]
        end
        
        prim["transform"] = transform_parts.empty? ? nil : transform_parts.join(" ")

        prim
      end

      # 6. SVG generation
      svg_width = canvas["width"]
      svg_height = canvas["height"]
      
      svg_lines = []
      svg_lines << %Q{<svg width="#{svg_width}" height="#{svg_height}" xmlns="http://www.w3.org/2000/svg">}
      
      primitives.each do |prim|
        svg_lines << generate_svg_element(prim)
      end
      
      svg_lines << "</svg>"
      svg_content = svg_lines.join("\n")

      # Structured vector representation
      vector_representation = {
        "view_id" => scene["view_id"],
        "canvas" => canvas,
        "primitives" => primitives,
        "non_claims" => non_claims
      }

      # Receipts
      receipt = {
        "hit" => false,
        "bound" => true,
        "animated" => true,
        "rendered" => true,
        "source_receipt_id" => source_receipt_id,
        "diagnostic_code" => "SUCCESS",
        "timestamp" => Time.now.iso8601,
        "non_claims" => non_claims
      }

      {
        receipt: receipt,
        vector: vector_representation,
        svg: svg_content
      }
    end

    private

    def self.validate_color_value!(val, node_id)
      return if val.nil?
      unless val.is_a?(String) && val.match?(/\A#(?:[0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})\z/)
        raise ValidationError.new("Invalid color value format '#{val}' on node '#{node_id}'", check_id: "NGUI-P6-8")
      end
    end

    def self.generate_svg_element(prim)
      attrs = []
      
      # Hardened SVG attributes validation and escaping
      escaped_id = CGI.escapeHTML(prim["id"])
      attrs << %Q{id="#{escaped_id}"}
      
      case prim["type"]
      when "rect"
        attrs << %Q{x="#{prim["x"]}"}
        attrs << %Q{y="#{prim["y"]}"}
        attrs << %Q{width="#{prim["width"]}"}
        attrs << %Q{height="#{prim["height"]}"}
      when "rounded_rect"
        attrs << %Q{x="#{prim["x"]}"}
        attrs << %Q{y="#{prim["y"]}"}
        attrs << %Q{width="#{prim["width"]}"}
        attrs << %Q{height="#{prim["height"]}"}
        attrs << %Q{rx="#{prim["rx"]}"}
        attrs << %Q{ry="#{prim["ry"]}"}
      when "circle"
        attrs << %Q{cx="#{prim["cx"]}"}
        attrs << %Q{cy="#{prim["cy"]}"}
        attrs << %Q{r="#{prim["r"]}"}
      when "text"
        attrs << %Q{x="#{prim["x"]}"}
        ty = prim["y"] + prim["size"] * 0.8
        attrs << %Q{y="#{ty}"}
        escaped_font = CGI.escapeHTML(prim["font"])
        attrs << %Q{font-family="#{escaped_font}"}
        attrs << %Q{font-size="#{prim["size"]}"}
      end

      if prim["fill"]
        escaped_fill = CGI.escapeHTML(prim["fill"])
        attrs << %Q{fill="#{escaped_fill}"}
      elsif prim["type"] != "text"
        attrs << %Q{fill="none"}
      end

      if prim["stroke"]
        escaped_stroke = CGI.escapeHTML(prim["stroke"])
        attrs << %Q{stroke="#{escaped_stroke}"}
        if prim["stroke_width"]
          attrs << %Q{stroke-width="#{prim["stroke_width"]}"}
        end
      end

      if prim["opacity"] && prim["opacity"] != 1.0
        attrs << %Q{opacity="#{prim["opacity"]}"}
      end

      if prim["transform"]
        escaped_transform = CGI.escapeHTML(prim["transform"])
        attrs << %Q{transform="#{escaped_transform}"}
      end

      if prim["type"] == "text"
        escaped_content = CGI.escapeHTML(prim["content"])
        %Q{  <text #{attrs.join(" ")}>#{escaped_content}</text>}
      else
        tag = prim["type"] == "rounded_rect" ? "rect" : prim["type"]
        %Q{  <#{tag} #{attrs.join(" ")} />}
      end
    end
  end
end
