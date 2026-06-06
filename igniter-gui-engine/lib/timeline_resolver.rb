# igniter-lab/igniter-gui-engine/lib/timeline_resolver.rb
# frozen_string_literal: true

# Status: experimental · lab-only · no-canon · no-stable-schema · no-performance-claim

require "json"
require "time"
require_relative "scene_tree"

module IgniterGui
  class TimelineResolver
    # Allowed properties for animation interpolation
    VALID_ANIM_PROPERTIES = %w[opacity transform_translate_x transform_translate_y transform_scale fill stroke].freeze

    # Allowed easing options
    VALID_EASINGS = %w[linear ease_in ease_out ease_in_out].freeze

    def self.resolve(bound_scene, manifest, time_ms)
      # Validate time_ms numeric type
      unless time_ms.is_a?(Numeric)
        raise ValidationError.new("Time offset 'time_ms' must be a Numeric value, got #{time_ms.class}", check_id: "NGUI-P5-8")
      end

      # 1. Parse manifest
      animations = []
      if manifest.is_a?(Hash) && manifest["animations"].is_a?(Array)
        animations = manifest["animations"]
      elsif manifest.is_a?(Array)
        animations = manifest
      else
        raise ValidationError.new("Malformed animation manifest: must be an Array or Hash with 'animations'", check_id: "NGUI-P5-7")
      end

      # Deep copy bound_scene to isolate layout frames
      resolved_scene = JSON.parse(JSON.generate(bound_scene))

      nodes_by_id = {}
      resolved_scene["bound_nodes"].each { |n| nodes_by_id[n["id"]] = n }

      animations.each do |anim|
        # Validate manifest keys (NGUI-P5-7)
        %w[target_id property from to duration_ms delay_ms easing].each do |k|
          unless anim.key?(k)
            raise ValidationError.new("Missing required animation key: '#{k}'", check_id: "NGUI-P5-7")
          end
        end

        target_id = anim["target_id"]
        # NGUI-P5-5: Unknown target node fails closed
        unless nodes_by_id.key?(target_id)
          raise ValidationError.new("Animation targets unknown node '#{target_id}'", check_id: "NGUI-P5-5")
        end

        property = anim["property"]
        # NGUI-P5-6: Unsupported animated property fails closed
        unless VALID_ANIM_PROPERTIES.include?(property)
          raise ValidationError.new("Unsupported animation property '#{property}'", check_id: "NGUI-P5-6")
        end

        easing = anim["easing"]
        # NGUI-P5-4: Easing whitelist check
        unless VALID_EASINGS.include?(easing)
          raise ValidationError.new("Unsupported easing function '#{easing}'", check_id: "NGUI-P5-4")
        end

        duration = anim["duration_ms"]
        delay = anim["delay_ms"]

        # Validate numeric types of delay/duration (NGUI-P5-8)
        unless duration.is_a?(Numeric) && delay.is_a?(Numeric)
          raise ValidationError.new("Animation duration and delay must be Numeric values", check_id: "NGUI-P5-8")
        end

        # NGUI-P5-8: Negative duration/delay fails closed
        if duration < 0 || delay < 0
          raise ValidationError.new("Animation duration and delay must be non-negative", check_id: "NGUI-P5-8")
        end

        # NGUI-P5-9: Excessive frame count / timeline safety bounds
        if duration > 10000 || delay > 5000 || (delay + duration) > 15000
          raise ValidationError.new("Animation timeline span exceeds safety bounds", check_id: "NGUI-P5-9")
        end

        # NGUI-P5-10: Invalid color/opacity/numeric value validation
        validate_animation_value_shapes!(property, anim["from"], anim["to"])

        # Compute active time fraction t
        if time_ms < delay
          t = 0.0
        elsif time_ms >= delay + duration
          t = 1.0
        else
          t = (time_ms - delay).to_f / duration
        end

        # Calculate easing fraction
        ease_t = calculate_ease(easing, t)

        # Apply interpolation
        target_node = nodes_by_id[target_id]
        style = target_node["style"] ||= {}

        case property
        when "opacity", "transform_scale", "transform_translate_x", "transform_translate_y"
          v1 = anim["from"].to_f
          v2 = anim["to"].to_f
          val = v1 + (v2 - v1) * ease_t

          style[property] = val

        when "fill", "stroke"
          val = interpolate_color(anim["from"], anim["to"], ease_t)
          target_node[property] = val
          style[property] = val
        end
      end

      resolved_scene
    end

    private

    def self.validate_animation_value_shapes!(property, from, to)
      case property
      when "opacity"
        [from, to].each do |val|
          unless val.is_a?(Numeric) && val >= 0.0 && val <= 1.0
            raise ValidationError.new("Opacity value must be Numeric within [0.0, 1.0], got #{val.class}", check_id: "NGUI-P5-10")
          end
        end
      when "transform_scale", "transform_translate_x", "transform_translate_y"
        [from, to].each do |val|
          unless val.is_a?(Numeric)
            raise ValidationError.new("Transform values must be Numeric, got #{val.class}", check_id: "NGUI-P5-10")
          end
        end
      when "fill", "stroke"
        [from, to].each do |val|
          unless val.is_a?(String) && val.match?(/\A#(?:[0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})\z/)
            raise ValidationError.new("Color animation values must be valid Hex color strings, got '#{val}'", check_id: "NGUI-P5-10")
          end
        end
      end
    end

    def self.calculate_ease(easing, t)
      case easing
      when "linear"
        t
      when "ease_in"
        t * t
      when "ease_out"
        t * (2.0 - t)
      when "ease_in_out"
        if t < 0.5
          2.0 * t * t
        else
          -1.0 + (4.0 - 2.0 * t) * t
        end
      else
        raise ValidationError.new("Unsupported easing function '#{easing}'", check_id: "NGUI-P5-4")
      end
    end

    def self.parse_hex(hex)
      hex = hex.sub(/\A#/, "")
      case hex.length
      when 3
        r = hex[0..0] * 2
        g = hex[1..1] * 2
        b = hex[2..2] * 2
        [r.hex, g.hex, b.hex, 255]
      when 4
        r = hex[0..0] * 2
        g = hex[1..1] * 2
        b = hex[2..2] * 2
        a = hex[3..3] * 2
        [r.hex, g.hex, b.hex, a.hex]
      when 6
        r = hex[0..1]
        g = hex[2..3]
        b = hex[4..5]
        [r.hex, g.hex, b.hex, 255]
      when 8
        r = hex[0..1]
        g = hex[2..3]
        b = hex[4..5]
        a = hex[6..7]
        [r.hex, g.hex, b.hex, a.hex]
      else
        raise ValidationError.new("Invalid hex color length", check_id: "NGUI-P5-10")
      end
    end

    def self.interpolate_color(from_hex, to_hex, t)
      r1, g1, b1, a1 = parse_hex(from_hex)
      r2, g2, b2, a2 = parse_hex(to_hex)

      r = (r1 + (r2 - r1) * t).to_i.clamp(0, 255)
      g = (g1 + (g2 - g1) * t).to_i.clamp(0, 255)
      b = (b1 + (b2 - b1) * t).to_i.clamp(0, 255)
      a = (a1 + (a2 - a1) * t).to_i.clamp(0, 255)

      if a == 255
        sprintf("#%02x%02x%02x", r, g, b)
      else
        sprintf("#%02x%02x%02x%02x", r, g, b, a)
      end
    end
  end
end
